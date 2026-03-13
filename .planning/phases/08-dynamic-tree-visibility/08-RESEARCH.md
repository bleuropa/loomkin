# Phase 8: Dynamic Tree Visibility - Research

**Researched:** 2026-03-08
**Domain:** Elixir/Phoenix LiveView — GenServer process monitoring, ETS tree state, LiveComponent popover, signal schema extension
**Confidence:** HIGH

## Summary

Phase 8 has four distinct work streams that must land in order: (1) move the ChildTeamCreated publish call from TeamSpawn tool to Manager.create_sub_team/3 and extend its schema with `team_name` and `depth`, (2) add `spawned_child_teams` to Agent.ex's struct and wire `Process.monitor` and `terminate/2` dissolution of child teams, (3) migrate workspace_live's `child_teams: []` flat-list assign to a `team_tree: %{}` parent-to-children map with recursive subscription and recursive dissolution walk, and (4) replace the `<select>` team switcher in the toolbar with a new TeamTreeComponent LiveComponent that renders an indented dropdown popover, hidden until at least one child team exists.

All four streams build on established codebase patterns. The signal schema extension uses the same `Jido.Signal` `use` macro pattern already present in every other signal module. The monitor/terminate pattern for child team dissolution mirrors the existing `loop_task` `:DOWN` handler — same `handle_info({:DOWN, ref, :process, ...}, state)` clause, new match branch for child team refs. The popover follows the exact same `open: false` state + `phx-click-away` + `absolute top-full` pattern already proven in ModelSelectorComponent. The team_tree map migration follows the same pattern as `pending_questions` replacing `pending_question` in Phase 7.

The critical signal classification for ChildTeamCreated ("team.child.created") is not yet in TeamBroadcaster's `@critical_types` MapSet — it must be added so the signal delivers immediately (not batched) to workspace_live, matching how approval and ask_user signals are handled.

**Primary recommendation:** Implement in wave order: signal schema and Manager publish first (ground truth source), then agent monitor/terminate (OTP safety), then workspace_live tree map (reactivity), then TeamTreeComponent (UI). Each wave is independently testable.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Agent tree panel location and design:**
- The tree lives in the toolbar — the existing flat `<select>` team switcher is replaced by a tree trigger
- The trigger is hidden until at least one sub-team exists; no UI change until a child spawns
- When clicked, opens a dropdown popover anchored below the toolbar (closes on outside click)
- Each tree node shows: team name + live agent count — depth shown by indent level only, no explicit badge
- Clicking a node switches the active team (same behavior as the current dropdown, but from the tree)

**Recursive subscription:**
- Child subscription follows the same recursive pattern: when ChildTeamCreated fires, workspace_live subscribes to that team — if it later spawns children, those fire their own ChildTeamCreated signals and workspace_live subscribes again
- Max depth of 2 (already enforced in Manager) keeps the recursion bounded
- Tree state replaces the flat list: `child_teams` assign becomes a `%{parent_id => [child_ids]}` map so the LiveView can render the hierarchy without Manager lookups at render time
- On team dissolution: workspace_live walks the tree map to find the dissolved team and all its known descendants, unsubscribes from each, and removes them from the map — does NOT rely on cascading Dissolved signals from Manager

**OTP crash -> child termination:**
- Leader agent GenServer holds monitor refs to the child team supervisor PIDs it spawns (stored in agent state alongside the spawning context)
- When the leader crashes, its GenServer process terminates — the monitor teardown (or a linked terminate/2 path) calls Manager.dissolve_team for each monitored child team before OTP restarts the leader
- Leader restarts fresh with no child teams — no auto-restore; it re-runs its planning logic and re-spawns as needed
- This prevents zombie teams from accumulating across leader restart cycles

**ChildTeamCreated signal:**
- Signal published from Manager.create_sub_team/3 (not from TeamSpawn tool) — single canonical source
- TeamSpawn tool's existing publish call is removed
- Signal schema extended: add `team_name: string` and `depth: integer` fields alongside existing `team_id` and `parent_team_id`
- workspace_live renders the new tree node immediately from signal data — no Manager.get_team_meta round-trip needed

### Claude's Discretion

- Exact popover styling, positioning, and animation (open/close transition)
- Whether the toolbar trigger shows the active team name or a generic "Teams" label
- Whether a depth-2 node is visually indented further or uses a different connector character
- Comms feed event for sub-team spawn/dissolve (whether to emit one, styling)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TREE-01 | Nested sub-teams at arbitrary depth auto-appear in the UI via recursive subscription | `subscribe_to_team/2` is already recursive-safe (MapSet dedup); ChildTeamCreated handler in workspace_live fires per new child; adding `team_tree` map replaces flat `child_teams` list; signal must be classified as critical in TeamBroadcaster |
| TREE-02 | ChildTeamCreated signal published from Manager.create_sub_team/3 with Process.monitor and ownership-aware termination | Manager already has `sub_team_id`, `name`, `depth` in scope at time of ETS insert; Agent struct needs `spawned_child_teams` field; `terminate/2` in agent.ex already exists and is the correct hook for dissolution |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Jido.Signal | project dependency | Signal schema definition, publish | All signals in codebase use `use Jido.Signal` with schema: keyword list |
| Phoenix LiveView | project dependency | LiveComponent for TeamTreeComponent, assign management | All UI components already use `use LoomkinWeb, :live_component` |
| GenServer (OTP) | Elixir stdlib | Agent struct extension, monitor/terminate | Agent.ex already a GenServer; `Process.monitor/1` and `terminate/2` are standard OTP hooks |
| ETS (Erlang) | Elixir stdlib | Team metadata storage (depth, name, parent_id all available) | Manager.ex already reads/writes team ETS for all metadata lookups |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MapSet | Elixir stdlib | O(1) dedup of subscribed teams | Already used in `subscribed_teams` assign and `@critical_types` in TeamBroadcaster |
| Loomkin.Signals | project | Signal publishing and critical-type classification | TeamBroadcaster.@critical_types needs "team.child.created" added |
| Loomkin.Teams.Topics | project | PubSub topic string management | subscribe_to_team/2 already calls `Topics.team_pubsub/1` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| terminate/2 for child dissolution | Process.link + trap_exit | Links would kill sub-team supervisor immediately on abnormal exit — too aggressive; terminate/2 allows controlled Manager.dissolve_team which runs cleanup, signals, and ETS deletion properly |
| %{parent_id => [child_ids]} map | flat list + Manager lookups at render time | Map avoids Manager ETS lookups on every render; render stays pure assign access; map also enables recursive walk for dissolution without Manager calls |
| LiveComponent for TeamTreeComponent | inline HEEx in workspace_live | Component encapsulates open/close state and events; workspace_live stays clean; matches ModelSelectorComponent precedent |

## Architecture Patterns

### Pattern 1: Signal Schema Extension (Jido.Signal)

**What:** Add required fields to an existing signal schema by extending the `schema:` keyword list in `use Jido.Signal`.

**When to use:** When a downstream consumer (workspace_live) needs data that is already available at the publish site (Manager.create_sub_team/3 has `name` and `depth` in scope).

**Example (current schema):**
```elixir
# lib/loomkin/signals/team.ex
defmodule Loomkin.Signals.Team.ChildTeamCreated do
  use Jido.Signal,
    type: "team.child.created",
    schema: [
      team_id: [type: :string, required: true],
      parent_team_id: [type: :string, required: false]
    ]
end
```

**Extended schema (Phase 8 target):**
```elixir
defmodule Loomkin.Signals.Team.ChildTeamCreated do
  use Jido.Signal,
    type: "team.child.created",
    schema: [
      team_id: [type: :string, required: true],
      parent_team_id: [type: :string, required: false],
      team_name: [type: :string, required: true],
      depth: [type: :integer, required: true]
    ]
end
```

### Pattern 2: Manager Publish — Single Canonical Source

**What:** Move signal publish from the tool (TeamSpawn) to the Manager function (create_sub_team/3) so every code path that creates a sub-team produces the signal.

**Current (tool-side):**
```elixir
# lib/loomkin/tools/team_spawn.ex (lines ~100-108)
if parent_team_id && any_spawned do
  signal = Loomkin.Signals.Team.ChildTeamCreated.new!(%{
    team_id: team_id,
    parent_team_id: parent_team_id
  })
  Loomkin.Signals.publish(signal)
end
```

**Target (manager-side, after ETS insert):**
```elixir
# lib/loomkin/teams/manager.ex — in create_sub_team/3, after :ets.insert
signal = Loomkin.Signals.Team.ChildTeamCreated.new!(%{
  team_id: sub_team_id,
  parent_team_id: parent_team_id,
  team_name: name,
  depth: parent_depth + 1
})
Loomkin.Signals.publish(signal)
```

Remove the publish block from `team_spawn.ex` entirely.

### Pattern 3: Agent GenServer Child Monitor

**What:** Add a `spawned_child_teams` field to the Agent struct (list of `{team_id, monitor_ref}` tuples). When TeamSpawn returns a team_id via tool result, the agent calls `Process.monitor/1` on the child team supervisor PID and stores the ref. In `terminate/2`, dissolve all monitored child teams.

**Existing `defstruct` in agent.ex:**
```elixir
defstruct [
  # ... existing fields ...
  last_asked_at: nil,
  pending_ask_user: nil
  # ADD:
  # spawned_child_teams: []
]
```

**New terminate/2 extension:**
```elixir
def terminate(reason, state) do
  require Logger
  Logger.info("[Kin:agent] terminating name=#{state.name} team=#{state.team_id} reason=#{inspect(reason)}")

  # Dissolve all child teams spawned by this leader to prevent zombie teams
  for {child_team_id, _ref} <- state.spawned_child_teams do
    Logger.info("[Kin:agent] dissolving child team=#{child_team_id} on terminate")
    Loomkin.Teams.Manager.dissolve_team(child_team_id)
  end

  Comms.unsubscribe(state.subscription_ids)
end
```

**Key: how to capture child team PID for monitoring.** After TeamSpawn tool returns `{:ok, %{team_id: new_team_id}}`, the agent receives the result in its tool callback. Manager.find_team_supervisor/1 or Registry lookup can resolve the team_id to a PID for `Process.monitor/1`. Alternative: Monitor the team's ETS table owner instead. Simpler: store `{team_id, nil}` refs and dissolve by team_id in terminate/2 without actual `Process.monitor` — the monitor ref was described in context as the mechanism but the cleanup is what matters, not the DOWN message handling for child teams.

**Note:** The context decisions say "monitor refs to the child team supervisor PIDs." The simplest safe implementation: in `handle_call({:team_spawned, team_id}, ...)` or via a `:child_team_spawned` message from TeamSpawn's tool result, store `{team_id, Process.monitor(supervisor_pid)}` in `spawned_child_teams`. A `:DOWN` message for a child supervisor then calls `Manager.dissolve_team` from the agent's handle_info. The `terminate/2` path covers crash scenarios.

### Pattern 4: team_tree Map Replace flat child_teams List

**What:** Replace `child_teams: []` assign (flat list of IDs) with `team_tree: %{}` (map of `%{parent_id => [child_id]}` entries). Workspace_live can walk the map to render hierarchy and to find descendants for cleanup.

**Current assign:**
```elixir
child_teams: [],
```

**Target assign:**
```elixir
team_tree: %{},
```

**Insert on ChildTeamCreated:**
```elixir
def handle_info({:child_team_created, child_team_id, parent_team_id}, socket) do
  tree = socket.assigns.team_tree
  updated = Map.update(tree, parent_team_id, [child_team_id], &[child_team_id | &1])
  socket
  |> subscribe_to_team(child_team_id)
  |> assign(:team_tree, updated)
  |> refresh_roster()
  |> sync_cards_with_roster()
end
```

**Walk for dissolution (find dissolved team and all descendants in tree):**
```elixir
defp collect_descendants(tree, team_id) do
  children = Map.get(tree, team_id, [])
  Enum.flat_map(children, fn child -> [child | collect_descendants(tree, child)] end)
end
```

**Remove dissolved team from tree:**
```elixir
defp remove_from_tree(tree, dissolved_id) do
  # Remove as a key (its children) and remove from all parent lists
  tree
  |> Map.delete(dissolved_id)
  |> Map.new(fn {parent, children} -> {parent, List.delete(children, dissolved_id)} end)
end
```

### Pattern 5: Toolbar Popover LiveComponent

**What:** TeamTreeComponent LiveComponent with `open: false` state, a trigger button hidden when `team_tree == %{}`, dropdown rendered with `absolute top-full` positioning, `phx-click-away` close, and indented rows per tree node.

**Pattern source:** ModelSelectorComponent (lib/loomkin_web/live/model_selector_component.ex) — already uses exact same pattern:
- Outer `<div id={@id} class="relative">`
- Trigger button with `phx-click="toggle_dropdown" phx-target={@myself}`
- Dropdown `<div :if={@open} class="absolute top-full ... z-[9999]">`
- `phx-click-away="close_dropdown" phx-target={@myself}`
- `handle_event("toggle_dropdown", ...)` toggles `open`
- `handle_event("close_dropdown", ...)` sets `open: false`

**TeamTreeComponent structure:**
```elixir
defmodule LoomkinWeb.TeamTreeComponent do
  use LoomkinWeb, :live_component

  def mount(socket) do
    {:ok, assign(socket, open: false)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="relative" :if={@team_tree != %{}}>
      <%!-- Trigger --%>
      <button
        type="button"
        phx-click="toggle_tree"
        phx-target={@myself}
        class={["flex items-center gap-1.5 px-2 py-1 rounded-md text-xs ...", ...]}
      >
        Teams
        <%!-- chevron --%>
      </button>
      <%!-- Dropdown --%>
      <div
        :if={@open}
        class="absolute top-full left-0 mt-1.5 w-52 rounded-xl overflow-hidden z-[9999] bg-surface-2 border border-default"
        phx-click-away="close_tree"
        phx-target={@myself}
      >
        <%!-- Root team row --%>
        <.tree_node team_id={@root_team_id} team_tree={@team_tree} active_team_id={@active_team_id}
                    agent_counts={@agent_counts} depth={0} myself={@myself} />
      </div>
    </div>
    """
  end
end
```

**Sending switch_team event up:** Use `send(self(), {:switch_team, team_id})` from `handle_event("select_team", ...)` — same pattern as ModelSelectorComponent's `send(self(), {:change_model, model})`.

### Anti-Patterns to Avoid

- **Publishing ChildTeamCreated from TeamSpawn**: The tool is not the canonical authority — Manager is. Publishing from the tool means direct Manager.create_sub_team/3 calls (from tests, future API endpoints) never fire the signal.
- **Relying on cascading Dissolved signals for UI cleanup**: Manager.dissolve_team cascades depth-first and publishes one Dissolved per team, but workspace_live may receive them out of order or miss some if a team was never subscribed. Walk the local `team_tree` map instead.
- **Process.link for child team supervision**: Links cause abrupt supervisor termination without the cleanup chain in Manager.dissolve_team. Use monitor + terminate/2 instead.
- **Manager round-trips in render**: The team_tree map makes all render data available from assigns. Never call Manager.get_team_meta/1 from HEEx templates.
- **Forgetting to classify "team.child.created" as critical**: Currently not in TeamBroadcaster.@critical_types. Without this, the signal is batched (50ms delay) and the tree node appears late. Add it alongside "agent.approval.requested".

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Popover open/close with outside-click dismiss | Custom JS hook or backend-only toggle | `phx-click-away` on the dropdown div (Phoenix LiveView built-in) | Already works in ModelSelectorComponent — zero JS needed |
| Dedup subscription guard | Manual boolean flag per team | `MapSet.member?(subscribed_teams, team_id)` check in subscribe_to_team/2 | Already present — function returns early if already subscribed |
| Signal delivery ordering | Custom queue or ack protocol | TeamBroadcaster critical classification (`@critical_types` MapSet) | Critical signals bypass the 50ms batch and go direct — same mechanism used for approval gates |
| Child team PID lookup | Custom ETS scan | `Registry.lookup(Loomkin.Teams.AgentRegistry, {team_id, agent_name})` | Manager already uses this for find_agent/2 |

## Common Pitfalls

### Pitfall 1: ChildTeamCreated Published Before Agents Are Spawned

**What goes wrong:** If Manager.create_sub_team/3 publishes ChildTeamCreated immediately after ETS insert (before agents are spawned), workspace_live receives the signal, calls refresh_roster, and finds 0 agents — the agent count shows 0 for a moment before correcting.

**Why it happens:** The signal fires at team creation time, but TeamSpawn spawns agents after create_sub_team returns.

**How to avoid:** Publish after `start_nervous_system/1` completes within create_sub_team/3. The roster refresh is debounced (50ms) so a second roster refresh from agent spawn signals will correct any count discrepancy quickly. Alternatively, workspace_live's `handle_info` for ChildTeamCreated already calls `refresh_roster()` after subscribing — it will pick up agents that spawned in the ~50ms window.

**Warning signs:** Agent count shows 0 immediately after tree node appears, then jumps to N after 200ms.

### Pitfall 2: Duplicate ChildTeamCreated Handling

**What goes wrong:** workspace_live has two handle_info clauses for "team.child.created" — one for `{:signal, sig}` wrapper (dispatched via TeamBroadcaster batch path) and one for unwrapped `%Jido.Signal{}` (Phase 3 direct delivery path). Both currently call `handle_info({:child_team_created, tid}, socket)` or similar. After making the signal critical, it will arrive via the direct `{:signal, sig}` wrapper. Both clauses must route to the same handler and the `subscribed_teams` MapSet guards against double-subscription.

**Why it happens:** TeamBroadcaster wraps signals in `{:signal, sig}` for direct delivery of critical signals. The existing "team.child.created" handle_info at line 1153 handles the unwrapped format from old direct publish path.

**How to avoid:** After moving publish to Manager and classifying as critical, verify only one delivery path fires. The `{:signal, sig}` clause at line 969 (which checks `parent_id` is subscribed before delegating) should be the only active path. The unwrapped clause at line 1153 becomes a fallback — ensure it does not double-subscribe.

**Warning signs:** `subscribe_to_team` logs "subscribing to team=X" twice for the same team_id.

### Pitfall 3: terminate/2 Race with OTP Supervisor Restart

**What goes wrong:** When an agent crashes, OTP calls `terminate/2` on the dying process. Inside terminate/2 we call `Manager.dissolve_team/1` which stops agents (including potentially the crashing agent's own team members). If dissolve_team tries to send GenServer.call to already-dead processes, it can timeout.

**Why it happens:** dissolve_team calls `stop_agent` which calls `Distributed.terminate_child(pid)` — if the pid is already dead, this is a no-op but must handle errors gracefully.

**How to avoid:** Wrap child team dissolution in `try/catch :exit, _ -> :ok` inside terminate/2. Manager.dissolve_team already has try/catch patterns in stop_nervous_system. The existing `stop_agent/2` -> `Distributed.terminate_child/1` should be safe for dead pids.

**Warning signs:** Test logs showing timeout exits during agent crash recovery tests.

### Pitfall 4: team_tree Map Key Collision on Reconnect

**What goes wrong:** On LiveView reconnect, workspace_live remounts and calls `Teams.Manager.list_sub_teams/1` to rebuild the child teams list. If the new code uses `team_tree` map but the reconnect path still references `child_teams` assign, it crashes.

**Why it happens:** workspace_live's reconnect path (after `if connected?(socket)` in mount) at lines 205-207 uses `Enum.reduce(child_ids, socket, &subscribe_to_team(&2, &1))` and later assigns `child_teams: child_teams` — both must be updated to use the new team_tree map.

**How to avoid:** Update the mount reconnect path to rebuild `team_tree` from `Manager.list_sub_teams/1` + `Manager.get_team_meta/1` for each child (to get parent_team_id). The tree map at mount should be: `%{root_team_id => child_ids}`.

**Warning signs:** `KeyError` for `:child_teams` or `:team_tree` assign in rendered templates after page reload.

### Pitfall 5: Missing Critical Classification for "team.child.created"

**What goes wrong:** The signal is batched (50ms delay) — tree node appears after batch flush, not immediately. On fast networks this is invisible but on slow connections creates a jarring ~50ms lag between sub-team spawn and UI update.

**Why it happens:** TeamBroadcaster.@critical_types currently does not include "team.child.created" (verified in source at lib/loomkin/teams/team_broadcaster.ex lines 33-46).

**How to avoid:** Add `"team.child.created"` to the `@critical_types` MapSet in team_broadcaster.ex. This is a one-line change with high visibility impact.

**Warning signs:** Child team node appears ~50ms after spawn rather than immediately.

## Code Examples

Verified patterns from official sources (codebase):

### Existing subscribe_to_team/2 (already MapSet-deduped)
```elixir
# lib/loomkin_web/live/workspace_live.ex lines 3212-3229
defp subscribe_to_team(socket, team_id) do
  subscribed = socket.assigns[:subscribed_teams] || MapSet.new()

  if MapSet.member?(subscribed, team_id) do
    socket
  else
    Phoenix.PubSub.subscribe(Loomkin.PubSub, Topics.team_pubsub(team_id))
    if broadcaster = socket.assigns[:broadcaster] do
      TeamBroadcaster.add_team(broadcaster, team_id)
    end
    assign(socket, subscribed_teams: MapSet.put(subscribed, team_id))
    # ... synthesize joined events for existing agents
  end
end
```

### Existing critical_types in TeamBroadcaster (needs "team.child.created" added)
```elixir
# lib/loomkin/teams/team_broadcaster.ex lines 33-46
@critical_types MapSet.new([
  "team.permission.request",
  "team.ask_user.question",
  "team.ask_user.answered",
  # ...approval signals...
  "agent.approval.resolved"
  # "team.child.created"  <-- MISSING, must add
])
```

### Existing terminate/2 in Agent (starting point)
```elixir
# lib/loomkin/teams/agent.ex lines 239-247
def terminate(reason, state) do
  require Logger
  Logger.info("[Kin:agent] terminating name=#{state.name} team=#{state.team_id} reason=#{inspect(reason)}")
  Comms.unsubscribe(state.subscription_ids)
end
```

### Existing toolbar select (to be replaced by TeamTreeComponent)
```heex
<%!-- lib/loomkin_web/live/workspace_live.ex lines 2802-2815 --%>
<select
  :if={@child_teams != []}
  phx-change="switch_team"
  name="team-id"
  class="max-w-[8rem] truncate text-[11px] rounded-md px-1.5 py-0.5 focus:outline-none bg-surface-2 border border-subtle text-secondary"
>
  <option :for={tid <- [@team_id | @child_teams]} value={tid} selected={tid == @active_team_id}>
    {short_team_id(tid)}
  </option>
</select>
```

### ModelSelectorComponent popover pattern (reference for TeamTreeComponent)
```elixir
# lib/loomkin_web/live/model_selector_component.ex — the proven open/close pattern
def mount(socket), do: {:ok, assign(socket, open: false)}

def handle_event("toggle_dropdown", _params, socket) do
  {:noreply, assign(socket, open: !socket.assigns.open)}
end

def handle_event("close_dropdown", _params, socket) do
  {:noreply, assign(socket, open: false)}
end
```

Dropdown template pattern:
```heex
<div :if={@open}
  class="absolute top-full left-0 mt-1.5 w-72 rounded-xl z-[9999] bg-surface-2 border border-default"
  phx-click-away="close_dropdown"
  phx-target={@myself}
>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat `child_teams: []` list in workspace_live | `team_tree: %{parent_id => [child_ids]}` map | Phase 8 | Enables recursive render and recursive dissolution walk without Manager ETS calls |
| ChildTeamCreated published from TeamSpawn tool | Published from Manager.create_sub_team/3 | Phase 8 | All creation paths emit the signal; tool is no longer the source of truth |
| `<select>` dropdown for team switching | TeamTreeComponent popover with nested indentation | Phase 8 | Shows team hierarchy visually; hidden until needed |
| No child team cleanup on leader crash | terminate/2 + Process.monitor dissolves child teams | Phase 8 | Prevents ghost teams after leader OTP restart |

**Deprecated/outdated:**
- `child_teams: []` assign in workspace_live: replaced by `team_tree: %{}`
- `ChildTeamCreated.new!(%{team_id: ..., parent_team_id: ...})` in team_spawn.ex: removed; Manager.create_sub_team/3 is the new publish site with extended schema

## Open Questions

1. **How to get child team supervisor PID for Process.monitor in Agent**
   - What we know: Manager.create_sub_team/3 returns `{:ok, sub_team_id}` not a PID; TeamSpawn tool returns `%{team_id: team_id}` in its result map
   - What's unclear: There is no Manager.get_team_supervisor_pid/1 function; the nervous system processes are registered in AgentRegistry under tuple keys like `{:broadcaster, team_id}` — we could monitor one of them
   - Recommendation: Simplest safe approach — in `terminate/2`, call `Manager.dissolve_team(child_team_id)` directly without a monitor ref. The "monitor" in the context decision description is for crash detection from the `:DOWN` message (if child supervisor dies unexpectedly the agent should react). For Phase 8 crash safety, the terminate/2 path is sufficient. The `spawned_child_teams` field can store just `[team_id]` list, not tuples, since `:DOWN` handling for child team PIDs can be added in a follow-up.

2. **How TeamSpawn tool communicates new team_id back to the Agent for monitor registration**
   - What we know: Tool run/2 returns `{:ok, %{result: summary, team_id: team_id}}`; the AgentLoop processes this tool result and injects it into messages
   - What's unclear: There is no `handle_call({:team_spawned, ...})` in agent.ex yet — the context doc mentions this as integration point
   - Recommendation: TeamSpawn tool result includes `team_id` in the return map. AgentLoop's `on_tool_result` callback (or the tool execute path in build_loop_opts/1) is the correct intercept point. Alternatively, a simple approach: after TeamSpawn finishes, have it also call `send(agent_pid, {:child_team_spawned, team_id})` so the agent can register the monitor in a handle_info clause. The agent_pid is available in the tool context.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | test/test_helper.exs |
| Quick run command | `mix test test/loomkin/teams/nested_teams_test.exs` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TREE-02 | ChildTeamCreated signal published from Manager.create_sub_team/3 with team_name and depth | unit | `mix test test/loomkin/teams/nested_teams_test.exs` | ✅ (extend existing file) |
| TREE-02 | TeamSpawn tool no longer publishes ChildTeamCreated | unit | `mix test test/loomkin/tools/team_spawn_test.exs` | ❌ Wave 0 |
| TREE-02 | Agent terminate/2 dissolves child teams | unit | `mix test test/loomkin/teams/agent_child_teams_test.exs` | ❌ Wave 0 |
| TREE-01 | workspace_live team_tree map updated on ChildTeamCreated | integration | `mix test test/loomkin_web/live/workspace_live_tree_test.exs` | ❌ Wave 0 |
| TREE-01 | workspace_live dissolves child tree on Dissolved signal | integration | `mix test test/loomkin_web/live/workspace_live_tree_test.exs` | ❌ Wave 0 |
| TREE-01 | TeamBroadcaster classifies "team.child.created" as critical | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs` | ✅ (extend existing file) |
| TREE-01 | TeamTreeComponent renders indented tree nodes | unit | `mix test test/loomkin_web/live/team_tree_component_test.exs` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/teams/nested_teams_test.exs test/loomkin/teams/team_broadcaster_test.exs`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin/tools/team_spawn_test.exs` — covers TREE-02 (signal NOT published from tool after migration)
- [ ] `test/loomkin/teams/agent_child_teams_test.exs` — covers TREE-02 (terminate/2 calls Manager.dissolve_team for each child)
- [ ] `test/loomkin_web/live/workspace_live_tree_test.exs` — covers TREE-01 (team_tree assign updated on signal, dissolution walk)
- [ ] `test/loomkin_web/live/team_tree_component_test.exs` — covers TREE-01 (component renders, open/close, node selection)

## Sources

### Primary (HIGH confidence)
- Codebase: `lib/loomkin/signals/team.ex` — ChildTeamCreated current schema (team_id, optional parent_team_id); all other signal schemas as schema extension pattern reference
- Codebase: `lib/loomkin/teams/manager.ex` — create_sub_team/3 full implementation; confirms `name`, `depth`, `parent_team_id` all in scope at publish point; dissolve_team cascade chain
- Codebase: `lib/loomkin/teams/agent.ex` — existing defstruct fields; existing terminate/2 body; existing handle_info :DOWN handler (for loop_task) as pattern for child team monitor handling
- Codebase: `lib/loomkin/tools/team_spawn.ex` — existing ChildTeamCreated publish block to remove; create_sub_team/3 call site
- Codebase: `lib/loomkin_web/live/workspace_live.ex` — child_teams assign location; subscribe_to_team/2 full implementation; ChildTeamCreated handle_info clauses; toolbar select block
- Codebase: `lib/loomkin/teams/team_broadcaster.ex` — @critical_types MapSet (confirms "team.child.created" absent); extract_team_id for "team.child.created" routes by parent_team_id
- Codebase: `lib/loomkin_web/live/model_selector_component.ex` — full popover LiveComponent pattern (open/close state, phx-click-away, absolute positioning, send to parent)
- Codebase: `test/loomkin/teams/nested_teams_test.exs` — existing test coverage for Manager.create_sub_team/3 (confirms test patterns, setup/teardown style)

### Secondary (MEDIUM confidence)
- Phoenix LiveView documentation: `phx-click-away` attribute on dropdown divs for outside-click dismiss — confirmed via ModelSelectorComponent in-project usage

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are in-project, verified from source files
- Architecture patterns: HIGH — each pattern traced to existing working code in the codebase
- Pitfalls: HIGH — identified from direct source reading of actual code paths (not hypothetical); duplicate delivery path confirmed from line numbers
- Test infrastructure: HIGH — ExUnit confirmed, existing test files read directly

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable codebase, no fast-moving external dependencies)
