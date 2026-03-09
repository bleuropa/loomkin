# Epic 10: Visibility Pipeline — Connecting Backend Intelligence to Frontend

## Problem Statement

The Loomkin backend has ~50 typed signal types, a per-team nervous system (AutoLogger, Broadcaster, Rebalancer, ConflictDetector), capabilities tracking, relevance scoring, conflict detection, collective decision-making with weighted voting, and cross-team knowledge propagation. Approximately 80% of this intelligence never reaches the UI.

The signal dispatch pipeline (`activity_event_from/1` in `workspace_live.ex`) flattens rich event types into generic categories. Several novel features have zero UI representation. The decision graph component never subscribes to live updates. Users see agent cards update and peer messages flow, but the sophisticated collaboration layer is invisible.

## Audit Results

### What WORKS (FE connected to BE)

- Agent status changes (working/idle/paused/error dots on cards)
- LLM streaming/thinking display (`agent.stream.start/delta/end` -> card `latest_content`)
- Tool execution display (`agent.tool.executing/complete` -> card `last_tool`)
- Peer messages in comms feed (`collaboration.peer.message` -> comms stream)
- Permission gates & spawn gates (full approval UI)
- Ask-user questions (agent-initiated questions with options)
- Cost tracking (`TeamCostComponent` subscribes directly to `agent.usage`, `agent.escalation`, `system.metrics.updated`)
- Agent crashes/recovery notifications (`agent.crashed/recovered/permanently_failed`)
- Team dashboard stats (`TeamDashboardComponent` subscribes to `agent.status`, `team.task.*`)

### What's INVISIBLE (BE emits, FE ignores)

| Feature | Backend | Frontend | Gap Type |
|---|---|---|---|
| Decision graph live updates | Emits `decision.node.added`, `pivot.created`, `logged` | Component never subscribes to signals | Missing subscription |
| Collaboration health score | `CollaborationMetrics` computes 0-100 | `collab_health` assign set but never rendered | Dead assign |
| Rebalancer escalations | Broadcasts `{:rebalance_needed, agent, task}` | No `handle_info` clause | Missing handler |
| Conflict detection | Emits `team.conflict.detected` with agent_a/agent_b/type | Mapped to generic `:error` in `activity_event_from` | Flattened event |
| Relevance scoring | `RelevanceScorer` filters discoveries by score 0.0-1.0 | Zero UI references | No UI |
| Smart assignment reasoning | `Tasks.smart_assign/2` picks by capability + load | No indicator of WHY | No UI |
| Collective voting/debate | Weighted voting with convergence tracking | Works internally, no tally/confidence UI | No UI |
| Collaboration events | 7 semantic types (consensus_reached, task_rebalanced, etc.) | Flattened to generic activity events | Flattened event |
| Capability evolution | ETS tracks per-agent success/failure per task type | Capability bars shown but no trend/learning visibility | Partial |
| Cross-team knowledge flow | Insights/blockers propagate to parent team | No visual indicator of cross-team flow | No UI |
| Context keeper lifecycle | `context.keeper.created`, `context.offloaded` signals | Shows in activity feed but no dedicated keeper inspector | Partial |

## Architecture Context

### Signal Flow (current)

```
Backend (Agent/Comms/Decision/etc.)
    | emit Jido.Signal
    v
TeamBroadcaster (per session, 50ms batching)
    | critical: immediate, batchable: buffered
    v
WorkspaceLive.handle_info({:team_broadcast, batch})
    | dispatch_signal/2 converts Signal -> tuple
    v
Tuple-based handle_info clauses (168+ patterns)
    |
    +-> forward_to_activity(socket, event)     -> TeamActivityComponent (send_update)
    +-> forward_to_cards_and_comms(socket, event) -> agent_cards map + comms_events stream
    +-> forward_to_dashboard(socket)            -> TeamDashboardComponent (send_update)
    +-> forward_to_cost(socket)                 -> TeamCostComponent (send_update)
```

### Key Files

| File | Lines | Purpose |
|---|---|---|
| `lib/loomkin_web/live/workspace_live.ex` | ~4200 | Main LiveView, all signal routing |
| `lib/loomkin_web/live/agent_card_component.ex` | ~900 | Per-agent card (status, thinking, tools) |
| `lib/loomkin_web/live/agent_comms_component.ex` | ~350 | Inter-agent comms feed |
| `lib/loomkin_web/live/decision_graph_component.ex` | ~250 | Decision graph visualization |
| `lib/loomkin_web/live/team_activity_component.ex` | ~400 | Activity feed with filters |
| `lib/loomkin_web/live/mission_control_panel_component.ex` | ~200 | Agent cards + comms container |
| `lib/loomkin_web/live/context_inspector_component.ex` | ~350 | Right panel focused agent view |
| `lib/loomkin/teams/team_broadcaster.ex` | ~300 | Signal batching/routing to LiveView |
| `lib/loomkin/teams/comms.ex` | ~250 | Inter-agent communication API |
| `lib/loomkin/teams/collaboration_metrics.ex` | ~150 | ETS-based health scoring |
| `lib/loomkin/teams/rebalancer.ex` | ~200 | Stuck agent detection |
| `lib/loomkin/teams/conflict_detector.ex` | ~400 | File/approach/decision conflicts |
| `lib/loomkin/teams/relevance_scorer.ex` | ~100 | Discovery-to-agent relevance |
| `lib/loomkin/teams/capabilities.ex` | ~150 | Per-agent task type performance |
| `lib/loomkin/decisions/auto_logger.ex` | ~200 | Agent events -> decision nodes |
| `lib/loomkin/decisions/broadcaster.ex` | ~150 | Decision changes -> agent notifications |

---

## 10.1: Decision Graph Live Updates (P0 — Critical)

### Problem

`DecisionGraphComponent` loads graph data on mount but never subscribes to signals. New decision nodes created by agents are invisible until page refresh.

### Backend (already working)

- `Graph.add_node/1` emits `Signals.Decision.NodeAdded` (`decision.node.added`)
- `Graph.pivot/2` emits `Signals.Decision.PivotCreated` (`decision.pivot.created`)
- `Comms.broadcast_decision/3` emits `Signals.Decision.DecisionLogged` (`decision.logged`)
- WorkspaceLive receives all three (lines 1314-1323) but only logs them to activity

### Frontend Fix

**File**: `lib/loomkin_web/live/decision_graph_component.ex`

1. In `update/2`, subscribe to decision signals scoped by team_id:
   ```elixir
   Loomkin.Signals.subscribe("decision.node.added")
   Loomkin.Signals.subscribe("decision.pivot.created")
   Loomkin.Signals.subscribe("decision.logged")
   ```
   Guard against double-subscription (store subscription IDs, unsubscribe on detach).

2. Add `handle_info/2` clauses for each signal type:
   ```elixir
   def handle_info(%Jido.Signal{type: "decision.node.added"} = sig, socket) do
     # Filter by team_id to avoid cross-team noise
     if sig.data[:team_id] == socket.assigns.team_id do
       # Reload graph data or append node to existing graph
       {:noreply, load_graph_data(socket)}
     else
       {:noreply, socket}
     end
   end
   ```

3. Pattern already exists in `TeamCostComponent` (lines 176-214) and `TeamDashboardComponent` (lines 95-175) — follow the same debounced reload approach.

### Acceptance Criteria

- [ ] New decision nodes appear in the graph within 1 second of creation (no page refresh)
- [ ] Pivot nodes show immediately with visual indicator (e.g., branch icon)
- [ ] Only nodes from the current team's graph appear (team_id scoping)
- [ ] No duplicate subscriptions on component re-mount

---

## 10.2: Collaboration Health Indicator (P0 — Critical)

### Problem

`CollaborationMetrics.collaboration_score/1` computes a 0-100 composite health score per team. The `collab_health` assign is set in WorkspaceLive (lines 61, 2543) but never rendered in any template.

### Backend (already working)

`CollaborationMetrics` tracks via ETS:
- `message_flow_count`, `discovery_share_count`
- `question_asked/answered_count`
- `task_completed/failed_count`
- `conflict_count`, `rebalance_count`, `consensus_count`

Composite formula:
- Activity: 0-40 (capped at 20 events)
- Resolution speed: 0-20
- Completion ratio: 0-20
- Conflict penalty: -5 per conflict (max -20)
- Base 20 offset

### Frontend Fix

**File**: `lib/loomkin_web/live/mission_control_panel_component.ex` or `workspace_live.ex` template

1. Add a health indicator widget to the mission control header or budget bar area:
   ```heex
   <div class="kin-health-indicator" title={"Collaboration Health: #{@collab_health}"}>
     <div class={[
       "kin-health-bar",
       @collab_health >= 70 && "health-good",
       @collab_health >= 40 && @collab_health < 70 && "health-moderate",
       @collab_health < 40 && "health-poor"
     ]} style={"width: #{@collab_health}%"} />
   </div>
   ```

2. Pass `collab_health` assign through to the component.

3. Periodically refresh: add a `Process.send_after(self(), :refresh_collab_health, 10_000)` timer in WorkspaceLive that calls `CollaborationMetrics.collaboration_score(team_id)`.

### Acceptance Criteria

- [ ] Health bar visible in the mission control area
- [ ] Color-coded: green (70-100), yellow (40-69), red (0-39)
- [ ] Tooltip shows breakdown of sub-scores
- [ ] Updates every 10 seconds while session is active
- [ ] Score reflects real collaboration events (not static)

---

## 10.3: Rebalancer Visibility (P1 — High)

### Problem

The Rebalancer detects stuck agents (5+ min inactive), nudges them, and escalates — but all of this is invisible. Nudges show as generic peer messages. Escalation broadcasts (`{:rebalance_needed, agent, task}`) have no `handle_info` clause and are silently dropped.

### Backend (already working)

**File**: `lib/loomkin/teams/rebalancer.ex`

- Nudge: `Comms.send_to(team_id, agent_name, {:nudge, ...})` — shows as peer message but unmarked
- Escalation (line ~170): Broadcasts `{:rebalance_needed, agent_name, task_info}` — **no handler**
- Tracks per-agent: `working_since`, `last_activity`, `nudge_counts`

### Frontend Fix

**File**: `lib/loomkin_web/live/workspace_live.ex`

1. Add signal type for rebalancer events. The rebalancer currently uses `Comms.broadcast/2` which wraps in a `collaboration.peer.message` signal. Either:
   - **(Option A)** Add a dedicated `team.rebalance.needed` signal type in `lib/loomkin/signals/team.ex` and emit it from `rebalancer.ex`
   - **(Option B)** Tag the existing peer message with `type: :rebalance` metadata and detect it in `forward_to_cards_and_comms`

2. In `forward_to_cards_and_comms/2`, detect rebalancer events and:
   - Set a `stuck_warning: true` flag on the agent card
   - Insert a `:rebalance` typed event into comms feed (with distinct icon/color)

3. In `agent_card_component.ex`, when `card.stuck_warning` is set:
   - Show a pulsing amber indicator on the card
   - Display "Stuck for X min" with nudge count

4. In `agent_comms_component.ex`, add `:rebalance` to the event config map with distinct styling (amber, clock/warning icon).

### Acceptance Criteria

- [ ] When an agent is stuck for 5+ min, its card shows an amber "stuck" indicator
- [ ] Nudge events appear in comms feed with distinct styling (not as generic peer messages)
- [ ] Escalation events appear prominently in comms feed
- [ ] Stuck indicator clears when agent resumes activity
- [ ] Nudge count visible (e.g., "Nudge 2/2 — escalating")

---

## 10.4: Conflict Detection UI (P1 — High)

### Problem

`ConflictDetector` identifies file-level, approach, and decision conflicts between agents. The signal is emitted but mapped to a generic `:error` in `activity_event_from/1`, losing all conflict-specific context (which agents, what type, what files).

### Backend (already working)

**File**: `lib/loomkin/teams/conflict_detector.ex`

Emits `Signals.Team.ConflictDetected` with payload:
```elixir
%{
  team_id: team_id,
  conflict_type: :file | :approach | :decision,
  agent_a: "coder-1",
  agent_b: "coder-2",
  description: "Both agents editing lib/loomkin/teams/agent.ex",
  files: ["lib/loomkin/teams/agent.ex"]  # for file conflicts
}
```

### Frontend Fix

**File**: `lib/loomkin_web/live/workspace_live.ex`

1. In `activity_event_from/1` (around line 4032), replace the generic `:error` mapping for conflict events:
   ```elixir
   defp activity_event_from({:conflict_detected, data}) do
     %{
       type: :conflict,
       agent: data.agent_a,
       content: data.description,
       metadata: %{
         conflict_type: data.conflict_type,
         agent_a: data.agent_a,
         agent_b: data.agent_b,
         files: Map.get(data, :files, [])
       }
     }
   end
   ```

2. In `forward_to_cards_and_comms/2`, when a conflict is detected:
   - Set `conflict: %{with: agent_b, type: type}` on both agents' cards
   - Insert a `:conflict` event into comms feed

3. In `agent_card_component.ex`, render conflict indicator:
   - Red pulse/border when agent has active conflict
   - Tooltip: "File conflict with {other_agent} on {files}"

4. In `agent_comms_component.ex`, add `:conflict` event type config with red styling, shield/warning icon, and expandable details showing the conflicting files/approaches.

### Acceptance Criteria

- [ ] Conflict events appear in comms feed with dedicated styling (not as generic errors)
- [ ] Both conflicting agents' cards show a red conflict indicator
- [ ] Conflict type is visible (file/approach/decision)
- [ ] Affected files listed in expandable details
- [ ] Conflict indicator clears when resolved

---

## 10.5: Smart Assignment Transparency (P1 — High)

### Problem

`Tasks.smart_assign/2` and `TeamSmartAssign` tool pick the best agent based on capability scores and current load, but the UI never shows why a task was assigned to a particular agent.

### Backend (already working)

**File**: `lib/loomkin/teams/capabilities.ex`

- `best_agent_for(team_id, task_type)` returns ranked `[{agent_name, score}]`
- `infer_task_type(title)` classifies tasks
- Score = `successes / (successes + failures) * log2(total + 1)`

**File**: `lib/loomkin/tools/team_smart_assign.ex`

- Picks top-ranked agent, falls back to least-loaded

### Frontend Fix

1. When `team.task.assigned` signal is received, enrich the comms event with assignment reasoning:
   - In `workspace_live.ex`, when handling task assignment, call `Capabilities.best_agent_for(team_id, inferred_type)` to get the ranking
   - Include `%{reason: "Best coder (score: 0.85, 12 tasks)", alternatives: [...]}` in event metadata

2. In the comms feed `:task_assigned` event, show a small expandable section:
   ```
   Task "Fix login bug" -> coder-1
   > coding score: 0.85 (7/8 success) | load: 1 task | runner-up: coder-2 (0.62)
   ```

3. On agent cards, show current task with a small capability badge when task type matches a strong capability.

### Acceptance Criteria

- [ ] Task assignment events in comms show WHY the agent was chosen
- [ ] Capability score and success rate visible
- [ ] Alternative agents listed with their scores
- [ ] Load factor visible (queued task count)

---

## 10.6: Relevance Scoring Visibility (P2 — Medium)

### Problem

`RelevanceScorer` computes a 0.0-1.0 score for each discovery-to-agent pair using keyword overlap (50%), filepath overlap (30%), and role alignment (20%). Discoveries are filtered before broadcast — but users can't see which agents received which discoveries or why.

### Backend (already working)

**File**: `lib/loomkin/teams/relevance_scorer.ex`
**File**: `lib/loomkin/teams/comms.ex` (lines 97-119, `broadcast_context_targeted`)

### Frontend Fix

1. When `context.update` signals arrive with targeted broadcast, include the relevance scores in the event:
   - Modify `broadcast_context_targeted/3` in `comms.ex` to emit a `context.discovery.targeted` signal with `%{recipients: [{agent, score}], skipped: [{agent, score}]}`
   - Or: tag the existing `context.update` signal with `recipients` metadata

2. In comms feed, when showing discovery events:
   ```
   Discovery: "Found auth module pattern in lib/auth/"
   > Sent to: coder-1 (0.87), researcher (0.72) | Filtered: tester (0.12)
   ```

3. Optional: in the context inspector (right panel), show a "Relevance Feed" tab listing what discoveries this agent received and their scores.

### Acceptance Criteria

- [ ] Discovery events in comms show which agents received them
- [ ] Relevance scores visible per recipient
- [ ] Filtered-out agents listed (helps users understand the scoring)
- [ ] Score breakdown available on hover/expand (keyword/filepath/role components)

---

## 10.7: Collective Decision & Debate Visibility (P2 — Medium)

### Problem

The consensus system runs full propose -> critique -> revise -> vote cycles with weighted voting, convergence tracking, oscillation detection, and deadlock strategies. All of this happens internally — users never see vote tallies, confidence levels, or debate progression.

### Backend (already working)

**Files**:
- `lib/loomkin/collaboration/collective_decision.ex` — quorum, voting, weighted scoring
- `lib/loomkin/collaboration/debate.ex` — multi-round propose/critique/revise/vote
- `lib/loomkin/collaboration/consensus_trail.ex` — logs rounds + convergence to decision graph

Emits:
- `collaboration.vote.response` — individual vote cast
- `collaboration.debate.response` — debate round response
- Decision graph nodes for each round via ConsensusTrail

### Frontend Fix

1. Add a new comms event type `:debate_round` with expandable UI:
   ```
   Debate Round 2/3: "API architecture approach"
   > Propose: REST with versioning (concierge, confidence: 0.8)
   > Critique: "GraphQL more flexible" (researcher, weight: 0.72)
   > Votes: REST 2.4 vs GraphQL 1.8 (quorum: majority)
   > Convergence: 67% -> 78% (+11%)
   ```

2. When `collaboration.vote.response` arrives, update the comms feed with live vote tally. Show vote weight breakdown (expertise x confidence).

3. When consensus is reached or deadlocked, show a prominent comms event with the outcome and final confidence score.

4. Link debate outcomes to decision graph nodes (ConsensusTrail already creates them — just need to make them clickable/navigable in the comms feed).

### Acceptance Criteria

- [ ] Active debates visible in comms feed with round progression
- [ ] Individual votes shown with agent name, position, and weight
- [ ] Running vote tally updates live
- [ ] Convergence percentage shown per round
- [ ] Final outcome (consensus/deadlock) prominently displayed
- [ ] Outcomes link to decision graph nodes

---

## 10.8: Cross-Team Knowledge Flow Indicator (P2 — Medium)

### Problem

When sub-team agents discover insights or hit blockers, `Comms.broadcast_context/3` with `propagate_up: true` sends the discovery to the parent team. This cross-team knowledge propagation is invisible.

### Backend (already working)

**File**: `lib/loomkin/teams/comms.ex` (lines 221-243)

- `:insight`, `:blocker`, `:discovery`, `:warning` types propagate up
- Payload includes `source_team` for traceability

### Frontend Fix

1. In comms feed, when a discovery has `source_team` metadata different from current team:
   - Show a "cross-team" badge/icon indicating it came from a sub-team
   - Display the source team name

2. In the team tree component, show a small animation/indicator when knowledge flows between teams (pulse on the edge connecting parent <-> child).

3. Add a `:knowledge_propagated` event type to comms with distinct styling (e.g., upward arrow icon, different background color).

### Acceptance Criteria

- [ ] Cross-team discoveries clearly labeled with source team
- [ ] Visual distinction from same-team discoveries in comms feed
- [ ] Team tree shows knowledge flow direction
- [ ] Blocker propagations highlighted more urgently than insights

---

## 10.9: Capability Evolution Timeline (P3 — Low)

### Problem

`Capabilities` tracks per-agent success/failure per task type in ETS. Agent cards show current capability bars, but there's no visibility into how capabilities evolve over a session — users can't see agents learning and improving.

### Backend (already working)

**File**: `lib/loomkin/teams/capabilities.ex`

- `record_task_result(team_id, agent_name, task_type, :success | :failure)`
- `get_capabilities(team_id, agent_name)` returns current scores
- Score = `successes / (successes + failures) * log2(total + 1)`

### Frontend Fix

1. In context inspector (right panel), when an agent is focused, add a "Capabilities" tab:
   - Show capability bars with success/failure counts
   - Show task history timeline: "coding: 5/6 success, last: 2m ago"

2. When a task completes (success/failure), briefly flash the relevant capability bar on the agent card to show learning.

3. Optional: emit a `agent.capability.updated` signal when a capability score changes, so the UI can animate the change.

### Acceptance Criteria

- [ ] Context inspector shows detailed capability breakdown per agent
- [ ] Success/failure counts visible alongside bars
- [ ] Capability bars flash/animate when scores change
- [ ] Task type labels human-readable

---

## 10.10: Context Keeper Inspector (P3 — Low)

### Problem

Context keepers are GenServers that store offloaded conversation context. They're created, queried, and persisted to DB — but the UI only shows "context offloaded" events in the activity feed. Users can't browse or query keepers.

### Backend (already working)

**Files**:
- `lib/loomkin/teams/context_offload.ex` — offload API
- `lib/loomkin/teams/context_keeper.ex` — per-topic GenServer
- Signals: `context.keeper.created`, `context.offloaded`

### Frontend Fix

1. In context inspector (right panel), add a "Keepers" tab listing all active context keepers for the current team:
   - Show keeper topic, source agent, creation time, token count
   - "Ask" button that lets the user query a keeper's knowledge

2. When `context.keeper.created` signal arrives, add the keeper to the list.

3. When a keeper is queried (via `ContextRetrieve` tool), show the query + response in the inspector.

### Acceptance Criteria

- [ ] Keepers tab lists all active keepers with metadata
- [ ] Users can ask questions to specific keepers
- [ ] Query results displayed inline
- [ ] Keeper count badge on tab

---

## Implementation Notes

### Priority Order

1. **P0** (10.1, 10.2): Decision graph + health indicator — highest impact, lowest effort
2. **P1** (10.3, 10.4, 10.5): Rebalancer + conflict + assignment — core collaboration visibility
3. **P2** (10.6, 10.7, 10.8): Relevance + debates + cross-team — advanced intelligence visibility
4. **P3** (10.9, 10.10): Capability timeline + keeper inspector — polish features

### Shared Patterns

All fixes follow the same architectural pattern already established by `TeamCostComponent` and `TeamDashboardComponent`:

1. Subscribe to signals in `update/2` (with duplicate guard)
2. Add `handle_info(%Jido.Signal{type: "..."})` clauses
3. Filter by `team_id` to scope events
4. Use debounced reload for expensive operations (500ms timer)

### Styling Convention

The codebase uses CSS custom properties and Tailwind. New event types in `AgentCommsComponent` follow the existing config map pattern:

```elixir
@event_configs %{
  conflict: %{icon: "shield-exclamation", color: "text-red-400", label: "Conflict"},
  rebalance: %{icon: "clock", color: "text-amber-400", label: "Rebalance"},
  debate_round: %{icon: "chat-bubble-left-right", color: "text-purple-400", label: "Debate"},
  knowledge_flow: %{icon: "arrow-up-circle", color: "text-cyan-400", label: "Knowledge"}
}
```

### Testing Strategy

- Each sub-task should include tests that verify:
  1. Signal is received by the component/LiveView
  2. Assign/stream is updated correctly
  3. Event scoping by team_id works
  4. No duplicate subscriptions on re-mount
- Use `Phoenix.LiveViewTest` with `render/1` and `has_element?/2`
- Test signal emission -> UI update end-to-end where possible

### Files That Will Be Modified (Most Tasks)

- `lib/loomkin_web/live/workspace_live.ex` — signal routing, `activity_event_from/1`, `forward_to_cards_and_comms/2`
- `lib/loomkin_web/live/agent_card_component.ex` — new indicators (stuck, conflict, capability flash)
- `lib/loomkin_web/live/agent_comms_component.ex` — new event type configs and templates
- `lib/loomkin_web/live/decision_graph_component.ex` — signal subscription + handle_info
- `lib/loomkin_web/live/context_inspector_component.ex` — new tabs (capabilities, keepers)
- `lib/loomkin_web/live/mission_control_panel_component.ex` — health indicator placement

### Already-Fixed Bugs (for context)

Two runtime bugs were fixed prior to this epic on branch `vt/visibility`:

1. **`session_id` type mismatch** (`agent.ex:195`): `session_id` defaulted to `team_id` (not a UUID) when no `:session_id` passed. Fixed: default to `nil`, pass real `state.id` from `session.ex`.

2. **GenServer calling itself** (`agent.ex:2188`): `self()` inside `on_tool_execute` closure returned Task PID, not Agent PID. Fixed: capture `agent_pid = self()` in `build_loop_opts/1` before the closure.
