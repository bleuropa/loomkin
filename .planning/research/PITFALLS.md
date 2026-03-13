# Domain Pitfalls

**Domain:** Multi-agent orchestration visibility and human-in-the-loop steering on the BEAM
**Project:** Loomkin — real-time agent team dashboard + intervention controls
**Researched:** 2026-03-07
**Confidence:** HIGH (derived from project codebase analysis + deep Elixir/OTP/LiveView domain knowledge)

---

## Critical Pitfalls

Mistakes that cause rewrites, data corruption, or fundamental usability failures.

---

### Pitfall 1: Subscribing to Every Agent Signal in workspace_live.ex

**What goes wrong:** The existing `workspace_live.ex` already tracks `subscribed_teams` as a MapSet and
subscribes to team-level signals. When adding agent-to-agent message visibility, the naive path is to
subscribe to the full `team.**` wildcard and filter in `handle_info/2`. With 5-10 concurrent agents each
emitting tool events, loop events, and inter-peer signals, the single LiveView process receives hundreds
of messages per second. Elixir's mailbox queues them sequentially. The LiveView falls behind real-time,
users see stale state, and the process risks hitting memory limits from queue backlog.

**Why it happens:** Signal bus subscriptions feel cheap because they are — until they are not. The existing
code already has this risk at the team level (`subscribed_teams` MapSet, `global_signals_subscribed` flag).
Adding per-agent or per-message-type subscriptions multiplies the pressure without changing the pattern.

**Consequences:**
- LiveView process mailbox grows unboundedly under concurrent agent activity
- UI lags seconds behind actual agent state
- Rerender storms as messages batch-deliver and trigger multiple full re-renders
- Hard to debug: symptoms look like "slow network" not "mailbox backlog"

**Prevention:**
- Introduce a `TeamBroadcaster` intermediary GenServer per team that aggregates, debounces (50ms windows),
  and summarizes agent events before forwarding to LiveView
- Use Phoenix.PubSub topic hierarchy so the LiveView subscribes to summary topics, not raw Jido Signal Bus
- Reserve direct Jido Signal Bus subscriptions for debug/inspector views that explicitly opt in
- For the agent activity feed, maintain a ring buffer (last 100 events) in the broadcaster and push diffs only

**Detection:**
- `:erlang.process_info(pid, :message_queue_len)` growing above 100 during multi-agent runs
- LiveView `handle_info` processing time > 50ms in telemetry
- Users report "the UI freezes when agents are talking"

**Which phase:** Live visibility (Phase 1) — must be designed correctly from the start; retrofitting
is painful because it requires changing subscription topology.

---

### Pitfall 2: Storing Full Agent Message History in LiveView Socket Assigns

**What goes wrong:** The existing concern documents `@max_messages 200` in socket assigns. The agent-to-agent
message stream adds a second message feed (peer signals, not just user-facing messages). If the agent comms
feed is stored directly in socket assigns alongside user chat history, a 5-agent team running 10 minutes
produces thousands of entries. Every new event triggers a LiveView diff against the full list. Phoenix diffs
the entire assigns structure on each `handle_info`, even with `@max_messages` guards, because the list
rebuilds on every update.

**Why it happens:** The natural implementation mirrors how `workspace_live.ex` already handles chat messages —
prepend to list, cap at N, assign to socket. It works for chat. It doesn't work for high-frequency agent streams.

**Consequences:**
- Full re-render of the message panel on every agent event (even unrelated ones)
- Server-side CPU spike with many concurrent teams
- Client-side DOM diffing cost grows with rendered message count
- Memory per socket balloons

**Prevention:**
- Use LiveView `:stream` (Phoenix LiveView 0.19+) for both agent comms feed and task event feeds —
  streams are append-only, DOM-diffed at the element level, no full list rerender
- Keep LiveView socket assigns for _current state_ (active agents, their statuses, current task), not _history_
- History goes in a dedicated `AgentCommsComponent` LiveComponent with its own stream and pagination
- Cap visible history client-side via CSS/virtual scroll, not by truncating the assigns list

**Detection:**
- LiveView render duration (`:telemetry` or LiveDashboard) climbing with agent count
- Chrome DevTools showing large DOM patch operations on every agent tick

**Which phase:** Live visibility (Phase 1) — wrong data model here requires refactor of the entire comms feed component.

---

### Pitfall 3: Conflating Pause/Resume with Permission-Pending State

**What goes wrong:** The existing codebase has two distinct agent halt states: `paused_state` (human-requested
pause) and `pending_permission` (awaiting human approval for a specific tool call). The CONCERNS.md already
flags that `pending_permission` can be overwritten by a second request, and there is no timeout. When adding
human intervention controls (pause, redirect, approval gates, confidence threshold triggers), it is tempting
to unify these into one "needs human" state. This causes a category error: a paused agent awaiting direction
is different from an agent that has stopped mid-tool-call awaiting permission. Resuming a paused agent
means giving it new instructions. Approving a permission means answering a yes/no for a specific action.
Mixing them leads to agents resuming with stale permission answers, or permission grants being interpreted
as resume commands, or (worst) the agent proceeding with a dangerous tool because a resume signal cleared
the permission gate.

**Why it happens:** Both states halt the agent loop and both surface to the human as "agent is waiting."
The UI temptation is one "Respond" button. The implementation temptation is one `awaiting` field.

**Consequences:**
- Agents execute dangerous tools after human meant to just give new instructions
- Stale permission responses (from previous session's question) resume wrong tool calls
- Race conditions: human pauses agent, agent simultaneously triggers permission request, both states lost

**Prevention:**
- Maintain two separate state machines with explicit types: `{:paused, reason, resume_guidance}` and
  `{:pending_permission, request_id, tool_name, args, timeout_at}`
- Permission requests must carry a `request_id`; responses that don't match current `request_id` are dropped
- Pausing an agent that is `pending_permission` should queue the pause, not clobber the permission state —
  the permission must be resolved (approved/denied) before pause takes effect
- Add explicit timeouts for both states with different behaviors: permission timeout = deny; pause timeout =
  keep paused (never auto-resume without human action)
- UI must show distinct control surfaces: approval gate is a binary yes/no with context, pause/resume is a
  direction input

**Detection:**
- Test scenario: agent requests permission, human pauses, human resumes with guidance, verify original
  permission request was not silently approved
- CONCERNS.md already flags: "pending_permission can be overwritten if new permission request arrives before
  user responds" — this must be fixed before adding more intervention types

**Which phase:** Human intervention controls (Phase 2) — foundational to getting intervention semantics right.

---

### Pitfall 4: Dynamic Supervision Trees That Leak Processes on Failure

**What goes wrong:** When a leader agent spawns child agents dynamically (`Teams.Supervisor`), the parent-child
relationship must be tracked so that if the leader crashes, its children are terminated (or at minimum,
stop receiving tasks). The naive approach links children to the supervisor but not to the leader GenServer.
When the leader crashes and is restarted by OTP, the old children are still running — orphaned — consuming
LLM budget, writing to shared state, and emitting signals that no one is listening to. A restarted leader
also spawns new children, so the child count doubles on each crash.

**Why it happens:** OTP supervisors restart children independently. If the leader spawning children is itself
a supervised child, its crash does not propagate downward to dynamically spawned grandchildren unless those
grandchildren are linked to the leader, not just the supervisor.

**Consequences:**
- Ghost agents running, consuming API budget, with no UI visibility (they are not in the active tree)
- Decision graph receiving writes from orphan agents, corrupting the graph
- Budget exceeded silently because orphan costs are tracked but not attributed to visible team
- Double-tree: restarted leader spawns a second set of children; now 2x agents working the same task

**Prevention:**
- Track the leader's PID as the "owner" of each child agent; store `spawned_by: leader_pid` in agent state
- Leader GenServer should monitor (`Process.monitor/1`) all children it spawns, not just use the supervisor
- On leader crash, its OTP `terminate/2` callback should send a shutdown signal to all children — use
  `Process.exit(child_pid, :leader_crashed)` for each tracked child
- `Teams.Supervisor` should support `terminate_tree(leader_pid)` to clean up all children belonging to a leader
- Before spawning children on restart, check for existing children from previous leader instance and
  terminate them first

**Detection:**
- Process count in `:sys.get_state/1` or `:erlang.system_info(:process_count)` grows across restarts
- Agent cost accumulation exceeding expected budget after a crash/restart cycle
- UI shows 3 agents but 6 are actually running (verify with `Process.list()` and agent registry)

**Which phase:** Dynamic tree spawning (Phase 3) — must be designed into the spawning protocol from day one.

---

### Pitfall 5: Real-Time Process Monitoring That Polls GenServer State

**What goes wrong:** To display agent status (running, paused, waiting for LLM, executing tool, idle) in the
dashboard, the straightforward approach is to `GenServer.call(agent_pid, :get_status)` on a timer. With
10 agents, this is 10 synchronous calls every 500ms from the LiveView process. This blocks the LiveView
for each call's round-trip, adds cross-process call overhead during active agent loops, and creates a
thundering herd when all calls fire simultaneously. Worse, `GenServer.call` during an active agent loop
(which may be inside a long LLM inference) queues behind the running loop message — the status response
comes back stale by definition.

**Why it happens:** "Get current state" is the natural mental model. `GenServer.call(:get_status)` reads
correct. OTP makes it easy. The cost is invisible until you have multiple agents.

**Consequences:**
- LiveView blocked for status poll round-trip on every tick
- Agents receive spurious status calls while running inference, causing mailbox pressure
- Status is always slightly stale (you are seeing state from before the loop processed your query)
- Poller and signal-based updates race, causing the UI to flicker between states

**Prevention:**
- Agent GenServers should push state changes proactively via `Phoenix.PubSub.broadcast/3` on every state
  transition, not be polled. State transitions are: `{:agent_status, agent_id, :running | :idle | :paused | :awaiting_permission | :awaiting_human | :tool_executing, metadata}`
- The TeamBroadcaster aggregates status events and maintains a last-known-state cache per agent
- LiveView subscribes to the broadcaster's summary topic; no direct GenServer calls for status
- If a point-in-time query is needed (e.g., debug inspector), use `GenServer.call` only in response to
  explicit user action (clicking "inspect"), never on a timer

**Detection:**
- Any `GenServer.call` inside a `Process.send_after` loop in LiveView code is this pitfall
- Agent process mailbox growing (`:erlang.process_info(agent_pid, :message_queue_len)`) under UI load

**Which phase:** Live visibility (Phase 1) — determines the entire observability architecture.

---

### Pitfall 6: Human Injection Creating Message Order Ambiguity

**What goes wrong:** When a human injects a message into an active agent team conversation (chat injection),
the message must land in a specific agent's context at a specific point in the conversation history. If the
agent is mid-loop (between LLM call and tool execution), the injected message arrives while the loop is
running. The loop's `messages` list is local to the running task — it is not the GenServer state, it is a
function argument being threaded through `do_loop/3`. The injection arrives as a GenServer message but the
GenServer is blocked waiting for the task. Two paths emerge: (1) the message is queued and appended after
loop completion — the human's guidance arrives after the agent has already committed to a course of action;
(2) the injection tries to interrupt the task — requiring `Task.shutdown` and restart with the new message
injected, which is complex and loses in-progress reasoning.

**Why it happens:** AgentLoop's design (message list passed through `do_loop/3`, not stored in GenServer state)
is the right separation of concerns but makes mid-loop injection genuinely hard. The existing queue management
in `agent.ex` handles new tasks but not mid-loop message amendments.

**Consequences:**
- Human guidance that arrives too late (after agent committed to the wrong tool call)
- Confusing UX: human types "stop, do X instead" — agent finishes what it was doing then sees the message
- Silent injection loss if queue is full or agent crashes before processing

**Prevention:**
- Use the existing checkpoint mechanism (`:post_llm`, `:post_tool` callbacks in `AgentLoop`) as injection
  points — injection is buffered until the next checkpoint, then prepended to messages list
- Add a `pending_injection` field to agent state; checkpoint callback checks this field before continuing
- The UI should reflect injection-pending state: "Your message will be delivered at the next agent checkpoint"
- For urgent injections (user wants to abort), expose the pause mechanism — pause first, then inject guidance,
  then resume — this is always safe regardless of loop position
- Never attempt mid-task `Task.shutdown` for injection; use checkpoint buffering

**Detection:**
- Test scenario: inject message while agent is in `Tool.Shell` execution; verify message appears in next
  iteration's context, not lost
- Verify injection delivery timing via telemetry events

**Which phase:** Human intervention controls (Phase 2).

---

## Moderate Pitfalls

Mistakes that cause incorrect behavior, UX confusion, or significant debugging cost.

---

### Pitfall 7: Confidence Threshold Triggers That Interrupt Constantly

**What goes wrong:** Agents auto-asking humans when uncertain (confidence threshold triggers) sounds useful
but the threshold calibration is nearly impossible to get right before seeing real usage data. Too low
a threshold and agents ask constantly ("Should I use tab or spaces?"), training users to ignore or batch-deny
all requests. Too high and agents never ask, defeating the purpose. The first iteration almost always
interrupts too often.

**Prevention:**
- Start with a high threshold (only ask on genuinely high-stakes decisions) and tune down, not the reverse
- Rate-limit confidence triggers: one ask per agent per N minutes maximum regardless of confidence score
- Batch multiple low-confidence decisions into a single human review: "Agent is uncertain about 3 things — review all"
- Provide the LLM with explicit examples of what warrants asking vs. proceeding in the system prompt
- Log all threshold triggers with the LLM's stated confidence and the decision made; use this to tune

**Detection:**
- User repeatedly dismissing agent questions without reading them
- Agent asking humans for decisions that the lead agent should be making autonomously

**Which phase:** Human intervention controls (Phase 2) — design threshold strategy before implementing trigger mechanism.

---

### Pitfall 8: Agent Tree Depth Without Cost Circuit Breakers

**What goes wrong:** When the leader decides tree depth autonomously based on task complexity, the LLM's
assessment of "complexity" has no ground truth. A poorly scoped task, an overly eager system prompt, or
a novel task type can cause the leader to spawn 20 agents across 4 levels. The existing cost tracking is
per-agent but there may be no hard ceiling on the total team cost for a single tree. By the time the human
sees the budget alarm, the spawning has already happened.

**Prevention:**
- Implement a pre-spawn budget check: before spawning any child agent, verify remaining team budget
  allows for at least N iterations of the new agent (N = conservative minimum, e.g., 5)
- Hard limit total depth (recommend max 3 levels for initial implementation; configurable)
- Hard limit total child count per leader (recommend max 8 immediate children; configurable)
- Emit a `tree_depth_decision` signal that the UI surfaces immediately when leader decides to spawn:
  "Leader will spawn 4 agents (est. cost: $X). [Approve] [Reduce to 2] [Override: Manual spec]"
- This approval gate should be on by default; toggle to "auto-approve within budget" for power users

**Detection:**
- Cost tracking spikes on new task submission before agents have done any work (spawning cost itself)
- `Teams.Supervisor` child count exceeds expected bounds

**Which phase:** Dynamic tree spawning (Phase 3).

---

### Pitfall 9: Orphaned Jido Signal Bus Subscriptions After Agent Termination

**What goes wrong:** When an agent is terminated (task complete, crashed, user-cancelled), its Jido Signal
Bus subscriptions may not be cleaned up. The Signal Bus holds references to the subscriber PID. Dead PIDs
receive signals silently (Elixir `send/2` to a dead PID is a no-op, no error), so the bus doesn't know
to clean up. Over time, the bus accumulates dead subscribers. This is mainly a memory issue but can also
cause unexpected signal delivery if PIDs are recycled (BEAM recycles PIDs, though rarely within a session).

**Prevention:**
- In `Teams.Agent.terminate/2`, explicitly call the Signal Bus unsubscribe for all active subscriptions
- Store the list of active subscriptions in agent state (subscription refs) so `terminate/2` can clean up
- Add a Signal Bus cleanup sweep (e.g., every 5 minutes) that pings each subscriber and removes dead ones:
  `Process.alive?(pid) || unsubscribe(sub)` — this is the safety net, not the primary cleanup

**Detection:**
- Signal Bus subscriber count growing after agents are terminated
- `:sys.get_state` on the Signal Bus GenServer showing subscriptions with PIDs that are not alive

**Which phase:** Live visibility (Phase 1) — subscriptions are established when adding visibility; cleanup must be paired.

---

### Pitfall 10: Decision Graph Writes from Orphan/Restarted Agents Creating Duplicate Nodes

**What goes wrong:** The decision graph (`Loomkin.Decisions`) is written to by agents via `AutoLogger`. When
a dynamic tree is involved and agents are restarted (OTP crash/restart cycle), a restarted agent that
continues a task from checkpoint may re-log decisions that the previous instance already logged, creating
duplicate or contradictory nodes in the DAG for the same logical decision.

**Prevention:**
- Decision nodes should carry an `agent_instance_id` (UUID generated at agent start, not agent role name)
  distinct from the agent's role or team position — this differentiates restarts
- Before inserting a decision node, check for an existing node with the same `(team_id, task_id, decision_key)`
  and upsert rather than insert
- On agent restart, pass the previous instance's `agent_instance_id` so it can query and continue from
  the existing decision context rather than starting fresh

**Detection:**
- Decision graph query returning duplicate nodes for the same task step
- `DecisionEdge` creating cycles (a symptom of conflicting nodes from restart)

**Which phase:** Dynamic tree spawning (Phase 3) — relevant when restarts become more frequent with deeper trees.

---

### Pitfall 11: Visibility UI Adding Latency to the Critical Path

**What goes wrong:** To show inter-agent messages in real time, the natural integration point is to
instrument the existing peer tools (`PeerAskQuestion`, `PeerReview`, `CollectiveDecision`) to emit
additional signals. If these signals are emitted synchronously (blocking the tool's `run/2` return),
every peer message gains the latency of signal bus dispatch plus subscriber processing. In a tight
consensus loop with 5 agents, this adds up.

**Prevention:**
- Visibility signals must be fire-and-forget: `Jido.Signal.Bus.publish_async/2` or equivalent, never
  blocking the tool's return path
- The visibility layer is strictly read-only from the agent's perspective — agents should not await
  acknowledgment from the UI
- If the Jido Signal Bus does not have async-safe publish, wrap it in `Task.start/1` inside the tool

**Detection:**
- Peer tool execution time increasing when the UI is open vs. closed
- Team consensus latency increases with observer count

**Which phase:** Live visibility (Phase 1).

---

### Pitfall 12: workspace_live.ex Growing Further (4,714 Lines + Visibility Features)

**What goes wrong:** The CONCERNS.md explicitly identifies `workspace_live.ex` as a 4,714-line monolith.
Adding agent team visibility (activity feed, agent tree diagram, task progress, intervention controls,
approval gates) to this file will push it past 6,000+ lines. Each new feature requires understanding
the entire file's state machine. Testing individual features becomes impossible. The "fix approach" in
CONCERNS.md (extract into LiveComponents) should happen before or during Phase 1, not after.

**Prevention:**
- Create `TeamDashboardLive` as a separate LiveView (new route) for team visibility rather than embedding
  in the existing workspace — this is the cleanest path
- If embedding is required, extract into dedicated LiveComponents before adding any visibility features:
  `AgentRosterComponent`, `AgentCommsFeedComponent`, `TaskTreeComponent`, `InterventionControlsComponent`
- Each component owns its own Signal Bus subscriptions and state; `workspace_live.ex` only orchestrates
  routing between components
- Target: workspace_live.ex becomes an orchestrator under 1,000 lines before this milestone ships

**Detection:**
- workspace_live.ex line count growing past 5,000 during feature development
- New features requiring changes scattered across 3+ locations in the file

**Which phase:** Live visibility (Phase 1) — refactoring must precede feature addition to avoid embedding in monolith.

---

## Minor Pitfalls

---

### Pitfall 13: Agent Status Labels That Don't Map to BEAM Process States

**What goes wrong:** Displaying "running / idle / thinking / executing tool" in the UI requires these
states to be explicit in agent GenServer state. If the implementation relies on inferring state from
task presence (`loop_task != nil` means running), the UI gets coarse-grained status that cannot
distinguish "LLM inference in progress" from "tool executing" from "between iterations."

**Prevention:**
- Add explicit `agent_phase` field to agent state with values like `:idle | :llm_inference | :tool_executing | :awaiting_permission | :awaiting_human | :paused | :consensus_voting`
- Update this field via the existing callback mechanism (`on_event` in `AgentLoop`) — no new coupling needed
- Broadcast phase changes as status events immediately on transition

**Which phase:** Live visibility (Phase 1).

---

### Pitfall 14: Hardcoding Team Signal Topics as Strings

**What goes wrong:** Signal Bus subscription topics like `"team.abc123.peer_message"` are constructed
with string interpolation throughout the codebase. As visibility adds new topic types (agent comms feed,
task status, approval gates, confidence triggers), ad-hoc topic strings proliferate and become hard to
trace. A typo in a subscription string silently drops all events.

**Prevention:**
- Create a `Loomkin.Teams.Topics` module that generates all team/agent signal topic atoms or validated strings:
  `Topics.agent_status(team_id, agent_id)`, `Topics.peer_message(team_id)`, `Topics.approval_gate(team_id)`
- All subscriptions and publications go through this module — never raw string interpolation
- This also makes grep-searchable what topics exist and who subscribes to them

**Which phase:** Live visibility (Phase 1).

---

### Pitfall 15: Approval Gate UX That Blocks the Entire Team

**What goes wrong:** If an approval gate pauses a single agent awaiting human sign-off, and that agent
is the leader, the entire team stalls. Specialists have no tasks to pick up, consensus requires the
leader, and the team burns time (and potentially incurs idle costs) waiting. Users may not notice the
approval gate is pending if it does not surface visually.

**Prevention:**
- Approval gate notifications must be high-visibility: persistent banner, not just a chat message
- When the leader is paused at an approval gate, emit a team-wide "leader waiting" signal so specialists
  can either continue independent tasks or also pause gracefully
- Design approval gates to be non-blocking where possible: the agent proposes the action and proceeds
  with a default, human can override within a time window

**Which phase:** Human intervention controls (Phase 2).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Agent comms feed in LiveView | Mailbox overload from high-frequency signals | TeamBroadcaster aggregator before LiveView (Pitfall 1) |
| Agent comms feed data model | Full list re-render on every event | LiveView `:stream` for append-only feeds (Pitfall 2) |
| Agent status polling | LiveView blocking GenServer.call to all agents | Push-based status events, never poll (Pitfall 5) |
| Visibility signal instrumentation | Adding latency to peer tool critical path | Fire-and-forget async signal publish (Pitfall 11) |
| Signal Bus subscriptions | Dead subscriber accumulation on agent exit | Explicit unsubscribe in `terminate/2` (Pitfall 9) |
| workspace_live.ex feature additions | Monolith grows past 6,000 lines | Extract LiveComponents first, then add features (Pitfall 12) |
| Pause vs. permission state | Two halt states collapsed into one | Separate state machines with typed fields (Pitfall 3) |
| Human chat injection | Guidance arrives after agent committed | Checkpoint-buffered injection, not mid-task interrupt (Pitfall 6) |
| Confidence threshold auto-ask | Constant interruptions training users to ignore | High threshold first, rate-limit, batch questions (Pitfall 7) |
| Dynamic child spawning | Orphan agents on leader crash/restart | Leader monitors children; `terminate/2` kills children (Pitfall 4) |
| Dynamic child spawning | Unbounded cost before human sees budget alarm | Pre-spawn budget check + approval gate on spawn plan (Pitfall 8) |
| Decision graph with restarts | Duplicate/contradictory nodes from restart | Agent instance IDs + upsert semantics (Pitfall 10) |

---

## Sources

All findings derived from:

- Direct analysis of project codebase (2026-03-07): `ARCHITECTURE.md`, `CONCERNS.md`, `PROJECT.md`
- Elixir/OTP process management knowledge: Phoenix LiveView mailbox model, GenServer state machine semantics,
  OTP supervision restart behaviors, `Process.monitor` vs. supervisor links
- Phoenix LiveView rendering model: assigns diffing, `:stream` for append-only lists, LiveComponent
  subscription isolation
- Jido Signal Bus: event-driven pub/sub on BEAM, subscriber cleanup lifecycle
- Human-in-the-loop AI systems: checkpoint-based injection patterns, approval gate UX, confidence threshold
  calibration principles
- Multi-agent orchestration on the BEAM: dynamic supervision tree ownership, cost attribution with dynamic
  spawning, signal topic namespace management
