# Phase 4: Task Graph & Crash Recovery - Research

**Researched:** 2026-03-07
**Domain:** LiveView SVG DAG visualization, OTP process monitoring, real-time crash recovery signals
**Confidence:** HIGH

## Summary

Phase 4 has two distinct but interconnected workstreams: (1) a task dependency graph rendered as an SVG DAG in a new sub-tab within the sidebar graph panel, and (2) OTP crash recovery visibility on agent cards via new signal types and a process watcher.

The codebase already provides nearly all the building blocks. DecisionGraphComponent is a fully functional SVG DAG renderer with layered layout, cubic bezier edges, arrowheads, click-to-inspect, and agent filtering -- it can be adapted wholesale for TaskGraphComponent. The Teams.Tasks context already has `blocked_task_ids/1`, `add_dependency/3` with `:blocks`/`:informs` dep types, and `auto_schedule_unblocked/1`. The TeamBroadcaster has critical signal bypass infrastructure. The Agent GenServer's `handle_info({:DOWN, ...})` already catches loop crashes but currently sets status to `:idle` instead of `:crashed`.

The key architectural challenge is crash detection at the *process* level (not just loop-task level). Agents are started under DynamicSupervisor as `:one_for_one` but with no explicit restart strategy on the child spec, meaning they default to `:permanent` restart. However, the Agent GenServer currently only monitors its internal `loop_task` (a Task.async), not the GenServer process itself. A separate AgentWatcher GenServer using `Process.monitor/1` is needed to detect GenServer-level crashes and broadcast crash/recovery signals before the 2-second target.

**Primary recommendation:** Build TaskGraphComponent by adapting DecisionGraphComponent patterns. Add AgentWatcher GenServer that monitors agent processes and publishes crash/recovered signals as critical types through TeamBroadcaster. Add new signal types to Loomkin.Signals.Agent.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Task graph lives in sidebar graph tab alongside DecisionGraphComponent, with sub-tabs "Tasks" and "Decisions" under the "Graph" label
- SVG DAG visual style matching DecisionGraphComponent -- layered layout, cubic bezier edges, arrowheads, node coloring
- Each task node displays: title, colored status indicator, assigned agent name
- Dependency edges: `:blocks` as solid arrows, `:informs` as dashed -- critical path highlighted with emphasized edges
- Click task node for detail panel below graph (consistent with DecisionGraphComponent pattern)
- Subtle transitions on task state changes (color transitions, edge fading)
- Crashed-but-recovering: red pulsing dot with "crashed" text, then amber "recovering", then normal
- Permanently dead (max restarts exceeded): card stays visible in red "failed" with "max restarts exceeded" banner
- Recovery history: persistent crash count badge (e.g., "1x crashed") for session duration
- Crash and recovery events in comms feed as system-level events with distinct type color
- Crash/recovery signals are critical (instant delivery, bypass 50ms batch)
- Task status changes batched normally (50ms window fine)
- Full graph loaded on mount, live updates via signals
- 2-second target for crash-to-recovered-on-card

### Claude's Discretion
- Exact sub-tab UI design within graph tab
- Task node sizing and spacing in DAG layout
- Critical path highlighting algorithm and visual treatment
- Crash count badge visual design
- "Recovering" transition timing and animation
- How to adapt DecisionGraphComponent patterns vs build fresh TaskGraphComponent

### Deferred Ideas (OUT OF SCOPE)
- Manual task actions from graph (reassign, cancel, unblock) -- future intervention phase
- Task filtering/search in graph view -- future phase
- Task time estimates and progress bars -- future phase
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VISB-03 | Task dependency graph displays blocked-by relationships visually (not just flat list) | TaskGraphComponent adapts DecisionGraphComponent SVG DAG pattern; TeamTaskDep schema already has `:blocks`/`:informs` dep types; Tasks.blocked_task_ids/1 query exists; full graph loaded from DB on mount with live signal updates |
| VISB-04 | OTP crash recovery reflected in UI -- crashed agent restarts show recovered status with no manual refresh | AgentWatcher GenServer monitors agent processes via Process.monitor; new Crashed/Recovered signal types added to Signals.Agent as critical types in TeamBroadcaster; AgentCardComponent extended with :crashed/:recovering status dot classes |
</phase_requirements>

## Architecture Patterns

### Recommended Project Structure
```
lib/
  loomkin/
    signals/
      agent.ex                    # Add Crashed + Recovered signal types
    teams/
      agent_watcher.ex            # NEW: GenServer monitoring agent processes
      agent.ex                    # Modify :DOWN handler to broadcast :crashed not :idle
      team_broadcaster.ex         # Add crash signal types to @critical_types
      tasks.ex                    # Add list_with_deps/1 query for graph data
  loomkin_web/
    live/
      task_graph_component.ex     # NEW: SVG DAG for task dependencies
      agent_card_component.ex     # Add :crashed, :recovering status support
      agent_comms_component.ex    # Add crash/recovery event type configs
      sidebar_panel_component.ex  # Add sub-tab routing (Tasks/Decisions)
      workspace_live.ex           # Handle new crash/recovery signals, graph refresh
```

### Pattern 1: Task Graph as Adapted DecisionGraphComponent
**What:** TaskGraphComponent follows the identical LiveComponent pattern: mount loads full graph from DB, update handles refresh_ref changes, SVG renders nodes and edges with layout_nodes/1, click-to-inspect shows detail panel.
**When to use:** This is the only approach -- locked decision.
**Key adaptation points:**
- Replace `@layer_order` with topological sort based on dependency edges (blocked-by determines vertical position)
- Replace `@node_type_colors` with task status colors (pending=gray, assigned=blue, in_progress=amber, completed=green, failed=red, blocked=orange)
- Add edge styling: solid for `:blocks`, dashed (stroke-dasharray) for `:informs`
- Add critical path highlighting (longest chain of blocking deps with incomplete tasks)

```elixir
# Task graph layout: topological layers based on dependency depth
defp layout_tasks(tasks, deps) do
  depth_map = compute_depths(tasks, deps)
  grouped = Enum.group_by(tasks, fn t -> Map.get(depth_map, t.id, 0) end)

  grouped
  |> Enum.sort_by(fn {layer, _} -> layer end)
  |> Enum.flat_map(fn {layer_y, layer_tasks} ->
    layer_tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, x_idx} ->
      %{task: task, x: 40 + x_idx * @node_gap, y: 40 + layer_y * @layer_gap}
    end)
  end)
end

defp compute_depths(tasks, deps) do
  task_ids = MapSet.new(tasks, & &1.id)
  # Build adjacency: for each dep, dependent task is "deeper" than its dependency
  blocks_deps = Enum.filter(deps, & &1.dep_type == :blocks)

  adj = Enum.reduce(blocks_deps, %{}, fn dep, acc ->
    if MapSet.member?(task_ids, dep.task_id) and MapSet.member?(task_ids, dep.depends_on_id) do
      Map.update(acc, dep.task_id, [dep.depends_on_id], &[dep.depends_on_id | &1])
    else
      acc
    end
  end)

  # BFS from roots (tasks with no blocking dependencies)
  roots = tasks |> Enum.filter(fn t -> not Map.has_key?(adj, t.id) end) |> Enum.map(& &1.id)
  bfs_depths(roots, adj, %{})
end
```

### Pattern 2: AgentWatcher for Process-Level Crash Detection
**What:** A GenServer that monitors agent processes via `Process.monitor/1` and publishes crash/recovery signals. Started per-team or globally.
**When to use:** Required because the current Agent GenServer only monitors its internal loop_task Task, not itself. When the GenServer process crashes and DynamicSupervisor restarts it, no signal is currently emitted.

```elixir
defmodule Loomkin.Teams.AgentWatcher do
  use GenServer

  @doc "Monitor an agent process and track its team/name for crash reporting."
  def watch(watcher, pid, team_id, agent_name) do
    GenServer.cast(watcher, {:watch, pid, team_id, agent_name})
  end

  def handle_cast({:watch, pid, team_id, agent_name}, state) do
    ref = Process.monitor(pid)
    agents = Map.put(state.agents, ref, {pid, team_id, agent_name, 0})
    {:noreply, %{state | agents: agents}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.agents, ref) do
      {{_pid, team_id, name, crash_count}, agents} ->
        # Broadcast crash signal immediately
        broadcast_crash(team_id, name, reason, crash_count + 1)
        # Schedule recovery check
        Process.send_after(self(), {:check_recovery, team_id, name, crash_count + 1}, 500)
        {:noreply, %{state | agents: agents}}
      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:check_recovery, team_id, name, crash_count}, state) do
    case Registry.lookup(Loomkin.Teams.AgentRegistry, {team_id, name}) do
      [{new_pid, _}] ->
        # Agent restarted -- monitor new process and broadcast recovery
        broadcast_recovered(team_id, name, crash_count)
        ref = Process.monitor(new_pid)
        agents = Map.put(state.agents, ref, {new_pid, team_id, name, crash_count})
        {:noreply, %{state | agents: agents}}
      [] ->
        # Not restarted yet -- retry or escalate
        if crash_count >= @max_retries do
          broadcast_permanently_failed(team_id, name, crash_count)
        else
          Process.send_after(self(), {:check_recovery, team_id, name, crash_count}, 500)
        end
        {:noreply, state}
    end
  end
end
```

### Pattern 3: Sub-Tab Routing in SidebarPanelComponent
**What:** Add a `graph_sub_tab` assign (`:tasks` or `:decisions`) and render the appropriate graph component.
**When to use:** Required by locked decision.

```elixir
# In SidebarPanelComponent
defp render_tab(:graph, assigns) do
  ~H"""
  <div class="flex flex-col h-full">
    <div class="flex gap-1 px-2 py-1.5 border-b border-gray-800/50">
      <button
        :for={sub <- [:tasks, :decisions]}
        phx-click="graph_sub_tab"
        phx-value-tab={sub}
        phx-target={@myself}
        class={[
          "px-2 py-1 text-[10px] font-medium rounded transition-colors",
          if(@graph_sub_tab == sub,
            do: "text-brand bg-brand/10",
            else: "text-muted hover:text-gray-300")
        ]}
      >
        {sub_tab_label(sub)}
      </button>
    </div>
    <div class="flex-1 overflow-auto">
      {render_graph_sub_tab(@graph_sub_tab, assigns)}
    </div>
  </div>
  """
end
```

### Anti-Patterns to Avoid
- **Polling for crash recovery:** Do NOT use periodic polling to check agent status. Use Process.monitor + signal push. Polling adds latency and defeats the 2-second target.
- **Embedding watcher logic in Agent GenServer:** The Agent cannot monitor itself for process-level crashes. A separate watcher process is required.
- **Re-querying full graph on every task signal:** Cache the graph data in the component and apply incremental updates from signals. Only full-reload on mount or session change.
- **Making agent status transitions synchronous:** Crash/recovery status changes must flow through signals (async) to maintain the established pattern. Do not add GenServer.call to check agent status from LiveView.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DAG layout algorithm | Custom graph layout from scratch | Adapt DecisionGraphComponent's layered layout with topological depth | Already proven, consistent visual language, handles edge cases |
| Process monitoring | Custom ETS-based alive checks | Process.monitor/1 + Registry.lookup/2 | BEAM primitive, zero overhead, instant notification |
| SVG edge rendering | HTML/CSS-based dependency lines | SVG cubic bezier paths (existing pattern) | Scales to complex graphs, arrowheads built-in, consistent |
| Critical signal delivery | New PubSub channel for crashes | TeamBroadcaster @critical_types MapSet | Infrastructure exists, just add types to the set |
| Topological sort | Custom recursive sort | Kahn's algorithm (BFS-based) | Simple, handles cycles gracefully (detect and warn), O(V+E) |

**Key insight:** This phase is 80% adaptation of existing patterns. The codebase has DecisionGraphComponent for the graph, TeamBroadcaster for signal routing, AgentCardComponent for status display, and AgentCommsComponent for event feed. The primary new code is AgentWatcher and the graph data query.

## Common Pitfalls

### Pitfall 1: Agent Restart Strategy Mismatch
**What goes wrong:** DynamicSupervisor uses `:one_for_one` strategy but Agent child spec may not have explicit restart configuration. Default for GenServer is `:permanent` which means it always restarts -- but the Agent uses `{:via, Registry, ...}` naming which may conflict on restart if the old name entry hasn't been cleaned up.
**Why it happens:** Registry entries are cleaned up asynchronously when a process dies. If DynamicSupervisor restarts too fast, the name may still be registered.
**How to avoid:** Verify the restart behavior empirically. The `:via` Registry should handle this because Registry monitors processes and cleans up on `:DOWN`, but there may be a race. If needed, add a small delay or use `:transient` restart and let AgentWatcher handle re-spawning.
**Warning signs:** `{:already_started, pid}` errors in logs after crash.

### Pitfall 2: Graph Layout Performance with Many Tasks
**What goes wrong:** Naive topological sort + layout on every signal update causes UI lag with 50+ tasks.
**Why it happens:** Re-laying out the entire graph on every status change is O(V+E) which compounds with frequent updates.
**How to avoid:** Cache the layout positions. Only re-run layout when graph structure changes (new tasks or deps added). Status changes only update node colors, not positions -- use CSS transitions for visual updates.
**Warning signs:** Visible jank when multiple tasks complete in rapid succession.

### Pitfall 3: Crash Count Persistence Across GenServer Restarts
**What goes wrong:** If AgentWatcher itself crashes, all crash counts are lost.
**Why it happens:** Crash count is in-memory state in AgentWatcher.
**How to avoid:** AgentWatcher should be started under the Teams.Supervisor with `:permanent` restart. Crash counts are session-scoped per the locked decision, so ETS or a simple Agent/GenServer with `:permanent` restart is sufficient. No need for DB persistence.
**Warning signs:** Crash badges resetting to 0 after infrastructure restarts.

### Pitfall 4: LiveView Re-render Thrashing on Batch Signals
**What goes wrong:** Task status batch signals trigger full graph re-render for each signal in the batch.
**Why it happens:** Each signal in a batch is processed sequentially, each calling `send_update/2` on the graph component.
**How to avoid:** Coalesce task signals in the batch handler. Increment a `refresh_ref` once per batch, not once per signal. The DecisionGraphComponent already uses this pattern (`refresh_ref` change triggers reload).
**Warning signs:** Multiple rapid re-renders visible as flickering in the graph.

### Pitfall 5: Missing Recovery Detection for Non-Restarted Agents
**What goes wrong:** Agent hits max restart intensity, DynamicSupervisor gives up, but UI still shows "crashed" indefinitely instead of "permanently failed."
**Why it happens:** AgentWatcher's recovery check keeps retrying but the process never comes back.
**How to avoid:** Set a max retry count in the recovery check loop (e.g., 5 checks at 500ms each = 2.5 seconds total). After that, broadcast a `permanently_failed` signal with escalation indicator.
**Warning signs:** Agent card stuck in "crashed" state forever.

## Code Examples

### New Signal Types for Crash/Recovery
```elixir
# In lib/loomkin/signals/agent.ex
defmodule Crashed do
  use Jido.Signal,
    type: "agent.crashed",
    schema: [
      agent_name: [type: :string, required: true],
      team_id: [type: :string, required: true],
      reason: [type: :string, required: false],
      crash_count: [type: :integer, required: false]
    ]
end

defmodule Recovered do
  use Jido.Signal,
    type: "agent.recovered",
    schema: [
      agent_name: [type: :string, required: true],
      team_id: [type: :string, required: true],
      crash_count: [type: :integer, required: false]
    ]
end

defmodule PermanentlyFailed do
  use Jido.Signal,
    type: "agent.permanently_failed",
    schema: [
      agent_name: [type: :string, required: true],
      team_id: [type: :string, required: true],
      crash_count: [type: :integer, required: false]
    ]
end
```

### Critical Types Addition in TeamBroadcaster
```elixir
@critical_types MapSet.new([
  "team.permission.request",
  "team.ask_user.question",
  "team.ask_user.answered",
  "agent.error",
  "agent.escalation",
  "team.dissolved",
  "collaboration.peer.message",
  # New crash/recovery signals
  "agent.crashed",
  "agent.recovered",
  "agent.permanently_failed"
])
```

### Task Graph Data Query
```elixir
# In lib/loomkin/teams/tasks.ex
def list_with_deps(team_id) do
  tasks = list_all(team_id)
  task_ids = Enum.map(tasks, & &1.id)

  deps =
    Repo.all(
      from d in TeamTaskDep,
        where: d.task_id in ^task_ids or d.depends_on_id in ^task_ids
    )

  {tasks, deps}
end
```

### Agent Card Crash Status Dot Classes
```elixir
# Additional status_dot_class clauses
defp status_dot_class(:crashed), do: "bg-red-500 animate-pulse"
defp status_dot_class(:recovering), do: "bg-amber-400 animate-pulse"
defp status_dot_class(:permanently_failed), do: "bg-red-600"

defp status_label(:crashed), do: "Crashed"
defp status_label(:recovering), do: "Recovering"
defp status_label(:permanently_failed), do: "Failed (max restarts)"
```

### Comms Feed Crash Event Types
```elixir
# Additional @type_config entries in AgentCommsComponent
agent_crashed: %{
  icon: "💥",
  accent_border: "rgba(239, 68, 68, 0.40)",
  accent_text: "#fca5a5",
  accent_bg: "rgba(239, 68, 68, 0.12)"
},
agent_recovered: %{
  icon: "🔄",
  accent_border: "rgba(251, 191, 36, 0.35)",
  accent_text: "#fcd34d",
  accent_bg: "rgba(251, 191, 36, 0.10)"
},
agent_permanently_failed: %{
  icon: "☠",
  accent_border: "rgba(185, 28, 28, 0.40)",
  accent_text: "#f87171",
  accent_bg: "rgba(185, 28, 28, 0.12)"
}
```

### Critical Path Algorithm
```elixir
defp compute_critical_path(tasks, deps) do
  # Critical path = longest chain of blocking dependencies with incomplete tasks
  blocks_deps = Enum.filter(deps, & &1.dep_type == :blocks)
  incomplete = MapSet.new(
    tasks |> Enum.reject(& &1.status == :completed) |> Enum.map(& &1.id)
  )

  # Build adjacency (dependency -> dependent)
  adj = Enum.reduce(blocks_deps, %{}, fn dep, acc ->
    if MapSet.member?(incomplete, dep.task_id) or MapSet.member?(incomplete, dep.depends_on_id) do
      Map.update(acc, dep.depends_on_id, [dep.task_id], &[dep.task_id | &1])
    else
      acc
    end
  end)

  # Find longest path from each root using DFS with memoization
  roots = MapSet.difference(
    MapSet.new(Map.keys(adj)),
    MapSet.new(Enum.flat_map(Map.values(adj), & &1))
  )

  {_depths, paths} =
    Enum.reduce(roots, {%{}, %{}}, fn root, {depths, paths} ->
      dfs_longest(root, adj, depths, paths)
    end)

  # Return edge pairs on the critical path
  case Enum.max_by(Map.to_list(paths), fn {_id, path} -> length(path) end, fn -> nil end) do
    nil -> MapSet.new()
    {_id, path} -> path_to_edge_set(path)
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Loop crash sets :idle | Should set :crashed then recover | This phase | Accurate crash visibility |
| No process-level monitoring | AgentWatcher monitors GenServer pids | This phase | Detects GenServer crashes, not just loop crashes |
| Single graph tab (decisions only) | Sub-tabbed graph panel | This phase | Both task and decision graphs accessible |
| Flat task list in workspace | Visual DAG with dependency edges | This phase | Blocked-by relationships visible at a glance |

**Current state of existing code:**
- Agent `:DOWN` handler (line 815): Sets status to `:idle` on loop crash -- needs to differentiate loop crash from GenServer crash and broadcast appropriate signal
- DynamicSupervisor (supervisor.ex line 26): `:one_for_one` strategy, no explicit max_restarts -- default is 3 restarts in 5 seconds
- Tasks.blocked_task_ids/1: Returns blocked IDs but no full dependency graph query -- needs `list_with_deps/1`
- TeamBroadcaster @critical_types: 7 types currently -- needs 3 more for crash signals

## Open Questions

1. **DynamicSupervisor max_restarts configuration**
   - What we know: Default is 3 restarts in 5 seconds for `:one_for_one`
   - What's unclear: Whether Agent child_spec overrides this. Need to check if `use GenServer` default child_spec sets restart to `:permanent`
   - Recommendation: Verify empirically by crashing an agent in dev. If restart works, the watcher pattern is viable. If agents are `:temporary` (no restart), the watcher needs to handle re-spawning via Manager.spawn_agent

2. **AgentWatcher lifecycle scope**
   - What we know: Need one watcher that can monitor agents across teams
   - What's unclear: Should it be global (started in Teams.Supervisor) or per-session?
   - Recommendation: Global singleton under Teams.Supervisor -- simpler, one process monitors all agents. Teams.Manager.spawn_agent calls AgentWatcher.watch after successful start.

3. **Crash count badge scope**
   - What we know: User wants "persistent for the session"
   - What's unclear: What defines "session" -- the LiveView mount lifetime or the team session?
   - Recommendation: Track in AgentWatcher (in-memory), delivered via signals. LiveView accumulates in assigns. If LiveView remounts, crash counts reset -- acceptable since page refresh = new session anyway.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in) |
| Config file | test/test_helper.exs |
| Quick run command | `mix test test/loomkin/teams/tasks_test.exs test/loomkin_web/live/sidebar_panel_component_test.exs -x` |
| Full suite command | `mix test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VISB-03a | TaskGraphComponent renders task nodes from DB | unit | `mix test test/loomkin_web/live/task_graph_component_test.exs -x` | Wave 0 |
| VISB-03b | Dependency edges rendered with correct style (solid/dashed) | unit | `mix test test/loomkin_web/live/task_graph_component_test.exs -x` | Wave 0 |
| VISB-03c | Task status change updates graph node without reload | unit | `mix test test/loomkin_web/live/task_graph_component_test.exs -x` | Wave 0 |
| VISB-03d | Sub-tab routing shows Tasks/Decisions graphs | unit | `mix test test/loomkin_web/live/sidebar_panel_component_test.exs -x` | Exists (needs update) |
| VISB-03e | list_with_deps returns tasks + dependencies | unit | `mix test test/loomkin/teams/tasks_test.exs -x` | Exists (needs new test) |
| VISB-04a | AgentWatcher detects process crash and publishes signal | unit | `mix test test/loomkin/teams/agent_watcher_test.exs -x` | Wave 0 |
| VISB-04b | Crash signal delivered as critical (instant, not batched) | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | Exists (needs new test) |
| VISB-04c | Agent card shows crashed status dot | unit | `mix test test/loomkin_web/live/workspace_live_test.exs -x` | Exists (needs update) |
| VISB-04d | Recovery detection within 2 seconds | integration | `mix test test/loomkin/teams/agent_watcher_test.exs -x` | Wave 0 |
| VISB-04e | Permanently failed agent shows escalation indicator | unit | `mix test test/loomkin_web/live/workspace_live_test.exs -x` | Exists (needs update) |
| VISB-04f | Crash events appear in comms feed | unit | `mix test test/loomkin_web/live/agent_comms_component_test.exs -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/teams/tasks_test.exs test/loomkin/teams/agent_watcher_test.exs test/loomkin_web/live/task_graph_component_test.exs -x`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin_web/live/task_graph_component_test.exs` -- covers VISB-03a, VISB-03b, VISB-03c
- [ ] `test/loomkin/teams/agent_watcher_test.exs` -- covers VISB-04a, VISB-04d
- [ ] `test/loomkin_web/live/agent_comms_component_test.exs` -- covers VISB-04f (may exist, needs crash event tests)

## Sources

### Primary (HIGH confidence)
- Codebase analysis: DecisionGraphComponent (824 lines) -- full SVG DAG pattern
- Codebase analysis: TeamBroadcaster -- critical signal MapSet, batch flush at 50ms
- Codebase analysis: Agent GenServer handle_info({:DOWN, ...}) at line 815 -- current crash handling
- Codebase analysis: Teams.Supervisor -- DynamicSupervisor :one_for_one, no custom max_restarts
- Codebase analysis: TeamTask schema -- status enum, TeamTaskDep -- dep_type :blocks/:informs
- Codebase analysis: AgentCardComponent -- existing :error status dot, card_state_class patterns
- Codebase analysis: SidebarPanelComponent -- current :graph tab renders only DecisionGraphComponent
- Codebase analysis: Signals.Agent -- existing signal type definitions using Jido.Signal

### Secondary (MEDIUM confidence)
- OTP DynamicSupervisor defaults: max_restarts=3, max_seconds=5 (Erlang/OTP 27 documentation)
- Process.monitor/1 delivers {:DOWN, ref, :process, pid, reason} synchronously to monitoring process (BEAM guarantees)
- Registry cleanup on process death is automatic and synchronous within the same node

### Tertiary (LOW confidence)
- None -- all findings verified against codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries and patterns already exist in the codebase
- Architecture: HIGH -- adapting proven DecisionGraphComponent + established signal infrastructure
- Pitfalls: HIGH -- identified from direct codebase analysis of restart behavior and signal flow
- Crash recovery: MEDIUM -- DynamicSupervisor restart behavior needs empirical verification (see Open Question 1)

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- internal codebase patterns, no external dependency changes expected)
