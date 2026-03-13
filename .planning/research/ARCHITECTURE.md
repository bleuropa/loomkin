# Architecture Patterns

**Domain:** Real-time multi-agent orchestration visibility and human-in-the-loop steering
**Researched:** 2026-03-07
**Confidence:** HIGH (derived entirely from first-party codebase analysis; no speculation)

---

## Recommended Architecture

The milestone adds four orthogonal concerns on top of the existing Teams/LiveView stack:

1. **Live agent tree visualization** — rendering the process hierarchy as a UI tree
2. **Real-time event streaming to UI** — surfacing every inter-agent signal to the browser
3. **Human intervention injection** — letting a human push messages into the agent graph
4. **Dynamic agent hierarchy management** — spawning child teams recursively, live

Each concern maps to a distinct component boundary. The architecture is **signal-bus-first**: all information already flows through Jido Signal Bus; the new work is mostly about subscribing to the right topics and rendering the right UI components.

---

## Existing Infrastructure (What Is Already There)

Understanding what is already built is critical — the architecture must integrate, not duplicate.

| Capability | Status | Location |
|---|---|---|
| Agent GenServer per agent | Exists | `Loomkin.Teams.Agent` |
| DynamicSupervisor for agents | Exists | `Loomkin.Teams.AgentSupervisor` |
| Registry for agents (name→pid) | Exists | `Loomkin.Teams.AgentRegistry` |
| Jido Signal Bus with wildcard subscriptions | Exists | `Loomkin.Signals.*` |
| `agent.status`, `agent.stream.*`, `agent.tool.*` signals | Exists | `Loomkin.Signals.Agent` |
| `team.task.*`, `team.ask_user.*`, `team.child.created` signals | Exists | `Loomkin.Signals.Team` |
| `collaboration.peer.message` signal | Exists | `Loomkin.Signals.Collaboration` |
| Parent/child team metadata in ETS | Exists | `Loomkin.Teams.Manager` |
| Sub-team depth limit + `list_sub_teams/1` | Exists | `Loomkin.Teams.Manager` |
| Agent checkpoint mechanism (pause/resume/steer) | Exists | `Loomkin.Teams.Agent.steer/2`, `request_pause/1`, `resume/2` |
| `AskUserQuestion` / `AskUserAnswered` signals | Exists | `Loomkin.Signals.Team` |
| `AskUserComponent` LiveView component | Exists | `LoomkinWeb.AskUserComponent` |
| Mission Control mode in WorkspaceLive | Exists | `LoomkinWeb.WorkspaceLive` (`:mission_control`) |
| Activity event feed (TeamActivityComponent) | Exists | `LoomkinWeb.TeamActivityComponent` |
| Comms feed (AgentCommsComponent) | Exists | `LoomkinWeb.AgentCommsComponent` |
| Human "steer" and "reply" injection paths | Exists | `WorkspaceLive.handle_event("send_message")` |
| `team_spawn` tool (recursive sub-team creation) | Exists | `Loomkin.Tools.TeamSpawn` |
| `ChildTeamCreated` signal on sub-team spawn | Exists | `Loomkin.Signals.Team.ChildTeamCreated` |
| WorkspaceLive subscribes to child team signals | Partial | `subscribe_to_team/2` called on `ChildTeamCreated` |

**Key insight:** The wiring between agents and the UI is substantially done. The gaps are in the rendering layer (tree view, stream focus), the human-steering UX (approval gates, confidence threshold triggers), and the dynamic tree spawning loop (leader triggers sub-team, which can itself spawn sub-agents).

---

## Component Boundaries

### Component 1: Team Tree Visualizer

**Responsibility:** Render the live agent hierarchy as an interactive tree. Show team nodes, agent nodes within each team, parent/child relationships, agent status, and task assignment. Must update live as teams are spawned or dissolved.

**Communicates with:**
- `Loomkin.Teams.Manager` — `list_sub_teams/1`, `list_agents/1`, `get_team_meta/1` for initial tree state
- Jido Signal Bus — `team.child.created`, `team.dissolved`, `agent.status` for live updates
- `WorkspaceLive` — receives the tree as assigns; clicking a node sets `focused_agent`

**Key signals consumed:**
- `team.child.created` → add child node to tree
- `team.dissolved` → remove node and descendants
- `agent.status` → update status dot on leaf node
- `team.task.assigned` / `team.task.completed` → show task label on node

**State shape:**
```elixir
%{
  tree: %{
    team_id: String.t(),
    name: String.t(),
    depth: non_neg_integer(),
    agents: [%{name: String.t(), role: atom(), status: atom(), task: String.t() | nil}],
    children: [team_node()]  # recursive
  }
}
```

**Build note:** The tree must be computed recursively using `Manager.list_sub_teams/1` and `Manager.list_agents/1`. Construct it once on mount, then patch via signal events rather than recomputing the full tree on every tick.

---

### Component 2: Real-Time Event Stream Bridge

**Responsibility:** Bridge Jido Signal Bus events to the LiveView process and normalize them into display-ready event structs. Acts as the translation layer between backend signals and UI event types.

**Communicates with:**
- Jido Signal Bus — subscribes to `agent.**`, `team.**`, `collaboration.**`, `context.**`
- `WorkspaceLive` — receives normalized `%{id, type, agent, content, timestamp, metadata}` structs via `push_activity_event/2` and `stream/3`
- `TeamActivityComponent` / `AgentCommsComponent` — render the event structs

**Existing:** The signal subscription and normalization logic already exists in `WorkspaceLive` but is partially implemented. The bridge needs to close gaps around:
- Streaming `agent.stream.delta` events with per-agent buffering
- Properly routing events to the right feed (activity vs comms) based on type
- Handling multi-team subscriptions (`subscribed_teams` MapSet already tracks this)

**Signal-to-event type mapping:**
```
agent.stream.start       → :stream_start (per agent)
agent.stream.delta       → :stream_delta (accumulated per agent)
agent.stream.end         → :stream_end
agent.tool.executing     → :tool_call (with pending state)
agent.tool.complete      → :tool_call (resolved)
collaboration.peer.message → :message (inter-agent)
context.update           → :discovery
team.task.assigned       → :task_assigned
team.task.completed      → :task_complete
team.ask_user.question   → :question (surfaces to human)
agent.error              → :error
agent.escalation         → :escalation
```

**Performance note:** With 10+ concurrent agents, stream deltas will arrive at high frequency. The existing `buffered_activity_events` assign and debounced roster refresh (50ms) patterns are the right approach. Apply the same debounce to metrics updates (already done with `metrics_debounce_ref`). Do not push every stream delta through `send_update/2` — accumulate in the LiveView socket state and batch-push.

---

### Component 3: Human Intervention Gateway

**Responsibility:** Provide multiple intervention patterns for the human: (a) chat injection into the active team conversation, (b) direct message/steer to a specific agent, (c) approval gate responses (permit/deny tool execution), (d) `AskUser` question answering, (e) agent pause/resume control.

**Communicates with:**
- `WorkspaceLive` — all intervention events arrive via `phx-click` / `handle_event`
- `Loomkin.Teams.Agent` — `steer/2`, `request_pause/1`, `resume/2`, `send_message/2`
- `Loomkin.Teams.Comms` — `broadcast/2` for team-wide injection
- `Loomkin.Signals.Team.AskUserAnswered` — published to Signal Bus to answer agent questions
- `Loomkin.AgentLoop` — checkpoint callback receives `{:pause, :user_requested}` from `request_pause`

**Patterns and their implementation hooks:**

| Pattern | Trigger | How It Works |
|---|---|---|
| Chat injection | Human types in composer, no `reply_target` | `Session.send_message/2` → normal architect pipeline |
| Direct reply to agent | `reply_target` set to `{agent, team_id}` | `Agent.send_message(pid, text)` |
| Steer paused agent | `reply_target` set to `{agent, team_id, :steer}` | `Agent.steer(pid, guidance)` |
| Request pause | Human clicks pause button on agent card | `Agent.request_pause(pid)` → checkpoint returns `{:pause, :user_requested}` |
| Approval gate | Agent hits permission pre-hook returning `{:ask, reason}` | `PermissionComponent` surfaces; human allows/denies; `AgentLoop.resume/3` |
| AskUser response | Agent emits `team.ask_user.question` signal | `AskUserComponent` renders; human picks option; `AskUserAnswered` signal published |
| Confidence-threshold trigger | Agent calls `AskUserQuestion` tool when confidence is low | Same as AskUser flow; threshold logic lives in agent system prompt / tool args |

**Key boundary:** The Gateway does NOT own any agent state. It translates human UI events into the correct API call on the appropriate GenServer or Signal Bus. State stays in the agent processes.

**New work needed:**
- Approval gate UI is partially wired (`PermissionComponent` exists). Need to connect `{:pending_permission}` return from `AgentLoop.run` through to `WorkspaceLive` as a pending permission event.
- Confidence-threshold triggers require a new tool (`AskUserQuestion`) that agents can call when they drop below a confidence level. The signal path already exists (`team.ask_user.question`). The tool does not exist yet.
- A "pause all agents" button for the team is not yet wired.

---

### Component 4: Dynamic Agent Tree Spawner

**Responsibility:** Enable a leader agent to recursively spawn child teams with sub-agents, have the UI auto-subscribe to those child teams, and enforce depth limits. The spawner is a data-flow concern, not a new process — it is the combination of the `team_spawn` tool, the `ChildTeamCreated` signal, and the WorkspaceLive subscription logic.

**Communicates with:**
- `Loomkin.Tools.TeamSpawn` — the leader calls this tool during its ReAct loop
- `Loomkin.Teams.Manager.create_sub_team/3` — creates child team in ETS with `parent_team_id`
- `Loomkin.Signals.Team.ChildTeamCreated` — published by `TeamSpawn` on success
- `WorkspaceLive.subscribe_to_team/2` — called when `ChildTeamCreated` arrives; auto-subscribes
- `Team Tree Visualizer` — receives tree update when child team is created

**Existing:** `TeamSpawn` and `create_sub_team` exist. `ChildTeamCreated` is published. `WorkspaceLive` listens for `ChildTeamCreated` and calls `subscribe_to_team`. The fundamental loop works.

**Gaps:**
- The tree visualizer (Component 1) does not yet exist to show the hierarchy visually.
- The depth limit enforcement (`@default_max_nesting_depth = 2`) is enforced server-side but is not surfaced to the UI.
- When a child team dissolves, `WorkspaceLive` does not remove it from `child_teams` assign or unsubscribe from its signals.
- The leader agent's prompt needs to be enriched with guidance on when/how to spawn sub-teams vs just assigning tasks within the same team.

---

## Data Flow

### Flow 1: Agent Action Visible in UI

```
Agent GenServer (Teams.Agent)
  → runs AgentLoop.run/2
  → AgentLoop emits on_event callback (:tool_executing, :stream_delta, etc.)
  → handle_loop_event/4 publishes Jido.Signal to SignalBus
  → SignalBus delivers to all subscribers
  → WorkspaceLive.handle_info(%Jido.Signal{type: "agent.tool.executing"}, socket)
  → normalize_signal_to_event/1 → %{id, type, agent, content, timestamp, metadata}
  → push_activity_event(socket, event)
  → send_update(TeamActivityComponent, id: "team-activity", new_event: event)
  → LiveView pushes diff to browser via WebSocket
```

### Flow 2: Human Steers an Agent

```
Human clicks "Reply to [agent]" on agent card
  → phx-click="set_reply_target" → WorkspaceLive.handle_event/3
  → assigns reply_target: %{agent: name, team_id: id}
  → Human types guidance and submits
  → phx-click="send_message" → WorkspaceLive.handle_event("send_message", ...)
  → reply_target present → Loomkin.Teams.Manager.find_agent(team_id, name)
  → Loomkin.Teams.Agent.send_message(pid, text)   [or .steer(pid, text) if :steer mode]
  → Agent receives message in handle_call → injected into message list → loop resumes
  → Agent signals flow back via Signal Bus → UI updates (Flow 1)
```

### Flow 3: Agent Asks Human a Question

```
Agent calls AskUserQuestion tool (or triggers confidence-threshold check)
  → tool publishes Signals.Team.AskUserQuestion signal
  → WorkspaceLive.handle_info receives "team.ask_user.question"
  → appends to pending_questions assign
  → AskUserComponent re-renders with new question card
  → Human clicks an option button
  → phx-click="ask_user_answer" → WorkspaceLive.handle_event/3
  → publishes Signals.Team.AskUserAnswered with {question_id, answer}
  → Agent is subscribed to "team.**" → receives AskUserAnswered
  → Agent resumes with human answer injected as context
```

### Flow 4: Dynamic Sub-Team Spawning

```
Leader agent runs team_spawn tool
  → Loomkin.Tools.TeamSpawn.run/2
  → Manager.create_sub_team(parent_team_id, spawning_agent, opts)
  → ETS updated with parent_team_id, depth, sub_teams list
  → Manager.spawn_agent(sub_team_id, ...) for each role
  → Signals.Team.ChildTeamCreated published
  → WorkspaceLive.handle_info receives "team.child.created"
  → subscribe_to_team(socket, child_team_id) subscribes to child signals
  → child_teams assign updated
  → Team Tree Visualizer receives new tree node
  → Child team agents begin running, their signals flow to UI (Flow 1)
```

### Flow 5: Approval Gate (Permission Pending)

```
Agent AgentLoop calls tool requiring permission
  → HookRunner.run_pre_hooks returns {:ask, reason}
  → AgentLoop enters :pending_permission state
  → Agent.handle_call({:loop_result, {:pending_permission, ...}})
  → broadcasts pending_permission signal to Bus
  → WorkspaceLive.handle_info receives it
  → pending_permissions assign updated
  → PermissionComponent renders with allow/deny buttons
  → Human clicks Allow or Deny
  → WorkspaceLive.handle_event("approve_permission" | "deny_permission")
  → Loomkin.AgentLoop.resume(agent_pid, :allow | :deny)
  → AgentLoop resumes from pending state
```

---

## Patterns to Follow

### Pattern 1: Signal-Bus-First Updates

All backend state changes emit a Jido Signal. UI components subscribe to relevant signal topics and update reactively. Never poll GenServers from LiveView for live state.

**Why:** Polling is O(agents) per tick and blocks the LiveView process. Signal delivery is async and fan-out is free.

### Pattern 2: Debounced Roster Refresh

High-frequency signals (tool complete, stream delta) should NOT trigger a full roster reload. Use the existing debounce pattern:

```elixir
defp schedule_reload(socket, agent_name) do
  if timer = socket.assigns[:reload_timer], do: Process.cancel_timer(timer)
  dirty = MapSet.put(socket.assigns[:dirty_agents] || MapSet.new(), agent_name)
  timer = Process.send_after(self(), :reload_dashboard, 500)
  assign(socket, reload_timer: timer, dirty_agents: dirty)
end
```

Apply this pattern to any component that reacts to frequent signals.

### Pattern 3: Buffered Activity Events

The `TeamActivityComponent` receives events via `send_update/2`, not via LiveView streams, so events survive tab-switch unmounts. The parent LiveView buffers events in `buffered_activity_events` and replays them on component remount via `reset_events:` assign.

New event types added for tree visualization, approval gates, and sub-team spawn must follow this pattern — they are stored in the LiveView socket, not the component state.

### Pattern 4: Checkpoint-Based Steering Interface

The `AgentLoop` checkpoint callback (`:post_llm`, `:post_tool`) is the injection point for human steering. The pattern is:

```elixir
# In Teams.Agent, checkpoint callback:
fn checkpoint ->
  GenServer.call(agent_pid, {:checkpoint, checkpoint}, 30_000)
end

# In Teams.Agent handle_call:
def handle_call({:checkpoint, _}, _from, %{pause_requested: true} = state) do
  {:reply, {:pause, :user_requested}, state}
end
```

Approval gates and confidence-threshold pauses should reuse this same checkpoint mechanism — the human's decision is the resume value.

### Pattern 5: ETS for Team Hierarchy, Registry for Agent Lookup

Team parent/child relationships are stored in ETS (`Loomkin.Teams.TableRegistry`). Agent PID lookup uses `Loomkin.Teams.AgentRegistry` (Registry). Do not introduce a new storage layer for the tree — query ETS to build the tree on mount, then patch with Signal events.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Polling Agent GenServers for Status

**What goes wrong:** LiveView timer polls `Manager.list_agents(team_id)` every second to detect status changes.
**Why bad:** With 10 agents across 3 teams, that's 30 GenServer.calls per second from a single LiveView process. Blocks the LiveView message queue.
**Instead:** Subscribe to `agent.status` signals. Agent emits status on every state transition. LiveView updates on signal arrival.

### Anti-Pattern 2: Pushing Stream Deltas Directly to Components

**What goes wrong:** Each `agent.stream.delta` signal triggers a `send_update(Component, ...)` with the delta character.
**Why bad:** A streaming LLM response can emit 50+ deltas per second. Each `send_update` is a GenServer message. At 5 streaming agents, that's 250 messages/second to one LiveView process.
**Instead:** Accumulate deltas in the LiveView socket (`streaming_content` per agent map), push via `stream/3` in batched intervals or only on `agent.stream.end`.

### Anti-Pattern 3: Rebuilding Full Tree on Every Signal

**What goes wrong:** Every `agent.status` signal causes the entire tree to be rebuilt by querying ETS.
**Why bad:** Tree rebuild is O(agents * teams). With deep nesting and many agents, this dominates at steady state.
**Instead:** Build the tree once on mount and on `team.child.created` / `team.dissolved`. For status updates, patch only the affected leaf node using the `agent_name` from the signal.

### Anti-Pattern 4: Letting Leaders Spawn Unbounded Sub-Teams

**What goes wrong:** Leader agent is given a complex task and spawns 10 sub-teams each with 5 agents, cascading to 50 concurrent LLM calls.
**Why bad:** Cost explosion, rate limiting cascade, no human visibility into the runaway spawn.
**Instead:** Enforce the existing `@default_max_nesting_depth = 2` strictly, add a max-agents-per-team cap (e.g., 6), and surface the spawning intent as a confirmation event (`team.spawn.requested`) that the human can approve or deny before the spawn executes. The existing `AskUser` pattern is the right model.

### Anti-Pattern 5: Using Phoenix PubSub Instead of Jido Signal Bus

**What goes wrong:** New code uses `Phoenix.PubSub.broadcast/3` for new event types instead of `Loomkin.Signals.publish/1`.
**Why bad:** Splits the event graph. AutoLogger, Broadcaster, ConflictDetector all listen only on the Jido Signal Bus. Events on PubSub are invisible to these nervous-system processes.
**Instead:** All new signals must be defined with `use Jido.Signal` and published via `Loomkin.Signals.publish/1`. `Loomkin.Signals.subscribe/1` wraps the bus subscription correctly.

---

## Suggested Build Order (Phase Dependencies)

The four components have the following dependency chain:

```
Component 2 (Event Stream Bridge)
  ← Component 1 (Tree Visualizer)    [tree needs events to stay live]
  ← Component 3 (Intervention Gateway) [intervention creates events the bridge shows]
  ← Component 4 (Dynamic Spawner)    [spawner events flow through the bridge]
```

### Phase 1: Close Signal Bridge Gaps (Foundation)

Build first because everything else depends on reliable signal-to-UI delivery.

- Audit all existing `handle_info` clauses in `WorkspaceLive` for missing signal types
- Add handlers for `agent.stream.delta` with per-agent accumulation
- Add handler for `team.child.created` → subscribe + update tree state
- Add handler for `team.dissolved` → unsubscribe + remove from tree state
- Normalize all collaboration signals to consistent event struct shape
- Ensure `AgentCommsComponent` receives peer messages from child teams

**Output:** Every signal type has a corresponding UI event. No dropped events.

### Phase 2: Agent Tree Visualizer (Visibility)

Build second because human intervention requires knowing which agent to target.

- New LiveComponent `AgentTreeComponent` (or extend `TeamDashboardComponent`)
- Build initial tree from `Manager.list_sub_teams/1` + `Manager.list_agents/1` recursively
- Update tree via signals (patch-not-rebuild approach)
- Tree nodes are interactive: clicking sets `focused_agent` in WorkspaceLive
- Show per-agent status dot, role badge, current task, cost so far

**Depends on:** Phase 1 (signal bridge) for live updates

### Phase 3: Human Intervention Controls (Steering)

Build third because it adds interactions on top of the visibility layer.

- Wire `PermissionComponent` to pending permission signals from AgentLoop
- Add pause/resume button to each agent card in the tree
- Implement confidence-threshold `AskUserQuestion` tool
- Approval gate confirmation flow (spawn-gating for large sub-team requests)
- Command palette entries for `pause all`, `steer [agent]`, `redirect [agent]`

**Depends on:** Phase 2 (tree knows which agents exist and their state)

### Phase 4: Dynamic Tree Spawning (Autonomy)

Build last because it requires the full visibility + intervention system to be safe.

- Enrich leader agent system prompt with sub-team spawning guidance
- Add spawn-gate: `team.spawn.requested` signal requires human confirm before executing
- Add max-agents-per-team enforcement in `Manager.spawn_agent/4`
- Wire tree visualizer to show spawning-in-progress state
- Implement leader-does-research-first pattern: leader spawns researcher sub-team, waits for results, then poses clarifying questions to human

**Depends on:** Phases 1-3 (must be able to see and control what spawns)

---

## Scalability Considerations

| Concern | At 3 agents, 1 team | At 10 agents, 3 teams | At 30 agents, 6 teams |
|---|---|---|---|
| Signal bus fan-out | Negligible | Moderate (10 signals/sec per streaming agent) | Requires per-agent stream batching |
| LiveView message queue | Easy | Watch for 50ms+ backlogs | Must debounce all high-freq signals |
| ETS tree queries | Fast | Fast | Fast (ETS reads are O(1)) |
| Registry lookups | Fast | Fast | Fast (Registry is concurrent) |
| UI render | Fast (few nodes) | Needs virtual list for comms feed | Needs pagination / windowing |
| LLM rate limits | Rarely triggered | Often triggered | Rate limiter is critical path |

The existing `RateLimiter` GenServer and `CostTracker` are the right scalability controls. The tree depth limit (`max_depth: 2`) is the primary safety valve on agent count.

---

## Sources

All findings derived from direct codebase analysis (HIGH confidence):

- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/agent.ex` — Agent GenServer, checkpoint, steer/pause/resume
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/manager.ex` — Team lifecycle, sub-team hierarchy, ETS registry
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/comms.ex` — Signal Bus wrapper, peer messaging
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/supervisor.ex` — OTP supervision tree structure
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/agent.ex` — All agent-domain signal types
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/team.ex` — All team-domain signal types
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/collaboration.ex` — Peer message signal types
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/tools/team_spawn.ex` — Dynamic sub-team spawning tool
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/workspace_live.ex` — Mission Control LiveView, signal subscriptions, event handling
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/team_dashboard_component.ex` — Existing agent/task display + signal handlers
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/agent_comms_component.ex` — Comms feed rendering
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/team_activity_component.ex` — Activity feed rendering
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/ask_user_component.ex` — AskUser question UI
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop.ex` — Checkpoint, permission pending, steer injection

---

*Analysis confidence: HIGH — all components verified against live source code, no training-data speculation.*
