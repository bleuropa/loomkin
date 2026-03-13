# Project Research Summary

**Project:** Loomkin — Agent Orchestration Visibility and Human-in-the-Loop Steering
**Domain:** Real-time multi-agent orchestration dashboard on the BEAM
**Researched:** 2026-03-07
**Confidence:** HIGH

## Executive Summary

Loomkin is a subsequent milestone on a production-quality multi-agent AI workspace built on Elixir/OTP, Phoenix LiveView, and the Jido agent framework. This milestone adds four interlocking capabilities: live visibility into the agent process tree, real-time inter-agent message streaming, human intervention controls (approval gates, confidence-threshold triggers, direct steering), and dynamic sub-team spawning with UI auto-discovery. Crucially, the research reveals that the infrastructure for all four capabilities is already largely built — the gap is in wiring, rendering, and closing known signal-delivery and state-machine holes, not in acquiring new technology. No new framework-level dependencies are required.

The recommended approach is signal-bus-first throughout: every backend state change already emits a Jido Signal; the new work is subscribing to the right topics and rendering the correct LiveComponents. The existing `AskUser` / `PermissionComponent` / `AgentCardComponent` / `TeamActivityComponent` patterns are the templates to follow for every new UI surface. The `workspace_live.ex` monolith (4,714 lines) must be refactored into dedicated LiveComponents before new visibility features are added — embedding further into the monolith is the single most reliable path to an unmaintainable system.

The primary risks are all performance-related: LiveView mailbox saturation under concurrent agent signal volume, full list re-renders from incorrect data models for the comms feed, and orphaned agent processes on leader crash. Each has a well-understood prevention using existing patterns (TeamBroadcaster intermediary, LiveView `:stream`, Process.monitor + terminate/2 cleanup). The secondary risk is semantic: conflating the pause state with the permission-pending state causes agents to execute dangerous tools after a human intended only to redirect them. These two states must be maintained as separate, typed state machines from day one.

---

## Key Findings

### Recommended Stack

The stack is locked and already running in production. This milestone requires no new library-level additions. The key extension points are all within the existing framework: `LiveView.stream/3` for the comms feed, `Jido.Signal.Bus` for new signal types (4 needed: `agent.peer_message`, `team.approval_gate.requested`, `team.approval_gate.resolved`, `agent.confidence.low`), `AgentLoop.Checkpoint` for approval gates, and `OTP.Process.monitor/1` for the agent tree health view.

The sole optional addition worth considering — D3.js for tree rendering — is explicitly not recommended. The existing `DecisionGraphComponent` already renders SVG DAGs in pure HEEX without JavaScript. The agent tree is a simpler structure and should follow the same pattern.

**Core technologies:**
- Phoenix LiveView 1.0 with `stream/3` — append-only comms feed diffing; already proven in `TeamActivityComponent`
- Jido Signal Bus (`jido_signal ~> 2.0`) — glob-path subscriptions, signal replay, typed structs; all new events route here, never Phoenix PubSub
- OTP DynamicSupervisor + Registry — dynamic agent lifecycle; `Process.monitor/1` drives tree health display
- `AgentLoop.Checkpoint` — the pause/resume/steer injection point; reused as the approval gate and confidence-threshold mechanism
- ETS (`Loomkin.Teams.TableRegistry`) — team hierarchy source of truth; build tree once on mount, patch via signals

For the complete version matrix see `.planning/research/STACK.md`.

### Expected Features

The codebase already ships substantial foundations: agent card grid, team activity feed, inter-agent comms component with 15 event types, pause/resume per agent, steer-on-pause, reply-to-agent, AskUser pending questions, collective-decide fallback, permission gates, dynamic sub-teams, cost tracking, queue management, and inspector mode. The milestone closes the gaps, not the foundations.

**Must have (table stakes — currently partial/missing):**
- Live agent-to-agent message stream wired for dynamically spawned sub-teams — the `AgentCommsComponent` exists but the bus subscription gap means child-team peer messages are dropped
- Newly spawned agents auto-insert into comms feed and agent card grid without reload — `ChildTeamCreated` signal exists but tree visualizer does not
- Error visibility with escalation-to-human alerts — error status dot exists; alert mechanism does not
- Chat injection broadcast to entire team conversation — reply-to-agent exists; team-wide broadcast has no UI entry point

**Should have (differentiators — currently partial/missing):**
- Confidence-threshold auto-ask pathway — `AskUserComponent` exists; the `AgentLoop`-to-signal-to-component wiring does not
- Checkpoint-based approval gates (distinct from permission hooks) — checkpoint mechanism exists; `RequestApproval` tool and `AskApprovalComponent` do not
- OTP-native process monitoring with UI reconciliation on crash/restart — supervision exists; UI update on restart does not
- Focused-agent inspector with full thinking stream — inspector mode and `focused_agent` state exist; full wiring needs validation

**Defer to later milestones:**
- Leader autonomously determines tree depth without human config (needs cost-bounded complexity heuristic)
- Leader-directed research phase before first human question (novel orchestration protocol; no existing pattern)
- Multi-user collaborative steering
- Full conversation replay / audit log UI
- Mobile-responsive orchestration UI

For the complete dependency graph see `.planning/research/FEATURES.md`.

### Architecture Approach

The architecture is organized around four component boundaries, all communicating through the Jido Signal Bus. The existing `WorkspaceLive` acts as the orchestrator; new capability surfaces as distinct LiveComponents with their own signal subscriptions and local state. The signal-bus-first rule is absolute: no GenServer polling, no Phoenix PubSub for new events, no mid-task interruption for human injection.

**Major components:**
1. **Event Stream Bridge** — closes the gap between existing signal subscriptions in `WorkspaceLive` and the full set of events the UI must handle; adds per-agent stream delta accumulation and multi-team routing
2. **Agent Tree Visualizer** (`AgentTreeComponent`) — renders the live process hierarchy using ETS on mount, `Process.monitor/1` for crash detection, signal patches for live updates; pure HEEX SVG, no JavaScript
3. **Human Intervention Gateway** — translates UI events into the correct API call on agent GenServers or Signal Bus; five interaction patterns (chat injection, direct reply, steer-on-pause, approval gate response, AskUser answer); state stays in agent processes
4. **Dynamic Agent Tree Spawner** — closes the loop from leader's `TeamSpawn` tool call through `ChildTeamCreated` signal to `WorkspaceLive` auto-subscribe and tree visualizer update; existing infrastructure, missing the dissolve cleanup path

The build dependency chain is: Event Stream Bridge first (everything else needs reliable signal delivery), then Tree Visualizer (intervention requires knowing targets), then Intervention Gateway (adds steering on top of visibility), then Dynamic Spawner (safe only with full visibility and control in place).

For data flow diagrams and anti-patterns see `.planning/research/ARCHITECTURE.md`.

### Critical Pitfalls

1. **LiveView mailbox saturation from raw signal bus subscriptions** — with 10+ concurrent agents, the single LiveView process cannot safely consume every raw Jido signal. Introduce a `TeamBroadcaster` GenServer per team that aggregates and debounces (50ms windows) before forwarding summaries to the LiveView. Reserve direct bus subscriptions for the debug inspector only.

2. **Full list re-render for the comms feed** — storing agent peer messages in socket assigns triggers a full diff on every new event. Use `LiveView.stream/3` for both the comms feed and the activity feed; this is already proven in `TeamActivityComponent`. History is not socket state; it belongs in the LiveComponent stream.

3. **Conflating pause state with permission-pending state** — these two halt states have different semantics: pause means "give me new direction," permission-pending means "answer yes/no for this specific tool." Mixing them causes agents to execute dangerous tools after the human intended to redirect. Maintain two separate, typed state machines. The CONCERNS.md already flags this as a known defect.

4. **Orphaned child agent processes on leader crash** — when a leader crashes and OTP restarts it, dynamically spawned children continue running as ghosts: consuming budget, writing to the decision graph, invisible in the UI. The leader must `Process.monitor/1` all its children and call `Process.exit(child_pid, :leader_crashed)` in its `terminate/2` callback. `Teams.Supervisor` needs a `terminate_tree(leader_pid)` function.

5. **`workspace_live.ex` monolith growth** — adding visibility features to the existing 4,714-line file will push it past 6,000+ lines and make the system untestable. Extract `AgentRosterComponent`, `AgentCommsFeedComponent`, `TaskTreeComponent`, and `InterventionControlsComponent` before adding any visibility feature. The target is `workspace_live.ex` under 1,000 lines as a pure orchestrator.

For the full list of 15 pitfalls including moderate and minor categories see `.planning/research/PITFALLS.md`.

---

## Implications for Roadmap

Research convergence across all four files points to the same four-phase structure: foundation first, then visibility, then steering, then autonomy. Each phase enables the next.

### Phase 1: Signal Bridge and Component Extraction (Foundation)

**Rationale:** Every downstream feature depends on reliable signal-to-UI delivery and a decomposed LiveView. The monolith refactor and signal-bridge gaps are blockers, not enhancements. Starting here means all subsequent phases build on solid ground rather than patching a failing system.

**Delivers:** Every signal type has a corresponding UI event with no drops; `workspace_live.ex` is an orchestrator under 1,000 lines; comms feed uses `LiveView.stream/3`; dead signal subscriptions are cleaned up in `terminate/2`; signal topics are generated through a `Loomkin.Teams.Topics` module.

**Addresses features from FEATURES.md:** Live agent-to-agent message stream for child teams; agent status subscription gaps for dynamically spawned agents.

**Avoids pitfalls:** Mailbox saturation (Pitfall 1), full list re-render (Pitfall 2), signal latency on critical path (Pitfall 11), orphaned subscriptions (Pitfall 9), monolith growth (Pitfall 12), hardcoded topic strings (Pitfall 14).

**Research flag:** Standard patterns — LiveView `stream/3`, GenServer debounce, signal bus subscriptions are all well-documented in the existing codebase. No deeper research needed.

---

### Phase 2: Live Agent Tree Visualizer (Visibility)

**Rationale:** Human intervention requires knowing which agent to target. The tree visualizer is the UI surface that answers that question. It must precede intervention controls because intervention without visibility is guesswork.

**Delivers:** `AgentTreeComponent` rendered as collapsible HEEX SVG tree; tree built from ETS on mount; patched via `team.child.created`, `team.dissolved`, and `agent.status` signals; `Process.monitor/1` on each agent PID for crash-immediate status; clicking a node sets `focused_agent`; per-node: role badge, status dot, current task, cost so far.

**Addresses features from FEATURES.md:** Dynamic tree spawning with UI auto-discovery; OTP-native process monitoring; focused-agent inspector wiring; error visibility with crash notification.

**Avoids pitfalls:** Full tree rebuild on every signal (Pitfall 3 — patch-not-rebuild pattern); agent status polling (Pitfall 5 — push-based status events only); coarse status labels (Pitfall 13 — explicit `agent_phase` field).

**Uses from STACK.md:** Pure HEEX SVG (no D3.js), `Process.monitor/1`, `Manager.list_sub_teams/1`, `Manager.list_agents/1`, `Loomkin.Signals.subscribe/1` for `agent.status` and `team.child.created`.

**Research flag:** Standard patterns — tree rendering in HEEX follows the existing `DecisionGraphComponent`. No deeper research needed.

---

### Phase 3: Human Intervention Controls (Steering)

**Rationale:** With the tree visible and signals reliable, human steering becomes safe to build. The approval gate, confidence threshold, and chat injection features all require knowing the current agent state (provided by Phase 2) and a working signal bridge (Phase 1).

**Delivers:** `RequestApproval` tool and `AskApprovalComponent` (checkpoint-based gates distinct from permission hooks); confidence-threshold `AskUserQuestion` tool wired from `AgentLoop` to `AskUserComponent`; chat broadcast injection to team conversation; explicit separate state machines for pause and permission-pending; "pause all agents" button; command palette entries for `pause all`, `steer [agent]`, `redirect [agent]`.

**Addresses features from FEATURES.md:** Confidence-threshold triggered ask-human; checkpoint-based approval gates; chat injection broadcast; error escalation to human.

**Avoids pitfalls:** Pause/permission state conflation (Pitfall 3 — two typed state machines required from day one); mid-loop injection race (Pitfall 6 — checkpoint-buffered injection, never `Task.shutdown`); confidence threshold over-triggering (Pitfall 7 — high threshold first, rate-limit, batch questions); approval gate blocking entire team (Pitfall 15 — high-visibility banner, parallel independent task continuation).

**Uses from STACK.md:** `AgentLoop.Checkpoint`, existing `AskUser` pattern (Registry-block-receive), `Teams.Agent.steer/2`, `Comms.broadcast/2`.

**Research flag:** Needs phase-specific research for two items: (1) LLM confidence extraction format — whether agents self-report via structured JSON, a special token, or a dedicated tool call is a prompt engineering decision not yet designed; (2) approval gate timeout UX — the timeout behavior for critical-path approvals needs explicit product design. All other patterns are standard.

---

### Phase 4: Dynamic Tree Spawning (Autonomy)

**Rationale:** Dynamic spawning is safe only with full visibility (Phase 2) and intervention controls (Phase 3) operational. The existing infrastructure (`TeamSpawn` tool, `ChildTeamCreated` signal, `WorkspaceLive` child subscription) already works for the happy path. This phase adds the safety rails and the leader-research protocol.

**Delivers:** Pre-spawn budget check and approval gate before leader spawns sub-teams; `tree_depth_decision` signal surfaced as UI confirmation event; dissolve cleanup (unsubscribe + remove from tree on `team.dissolved`); max-agents-per-team enforcement in `Manager.spawn_agent/4`; leader system prompt enrichment with sub-team spawning guidance; one-line fix to publish `ChildTeamCreated` in `Manager.create_sub_team/3` (currently omitted); `terminate_tree(leader_pid)` function in `Teams.Supervisor`.

**Addresses features from FEATURES.md:** Dynamic tree spawning with UI auto-discovery (complete); OTP restart reconciliation (crashed agent reappears in UI).

**Avoids pitfalls:** Orphaned child processes on leader crash (Pitfall 4 — leader monitors children, terminate/2 kills them); unbounded spawning cost (Pitfall 8 — pre-spawn budget check + human approval gate); duplicate decision graph nodes on restart (Pitfall 10 — agent instance IDs, upsert semantics).

**Research flag:** Needs phase-specific research for leader-directs-research-before-asking protocol. No existing pattern in the codebase; requires designing the orienter/researcher role sequence, how the leader waits for synthesis before posing clarifying questions, and how cost attribution works across the research sub-team.

---

### Phase Ordering Rationale

- **Dependency chain is explicit:** Signal bridge (Phase 1) is a hard prerequisite for all subsequent phases. Tree visualizer (Phase 2) is a hard prerequisite for steering (Phase 3). Full visibility and control (Phases 1-3) are prerequisites for safe dynamic spawning (Phase 4).
- **Risk front-loading:** The three critical pitfalls that would require rewrites (mailbox saturation, wrong data model for comms feed, pause/permission state conflation) are all addressed in Phases 1-2. Later phases build on a validated foundation.
- **Monolith refactor in Phase 1:** The `workspace_live.ex` extraction must happen before any new UI feature is added. Deferring the refactor means every subsequent phase compounds the technical debt.
- **Anti-features are firm:** Leader-directed research phase before human questions, full conversation replay, multi-user steering, and mobile UI are all explicitly deferred. Scope pressure during planning should not reopen these.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3:** LLM confidence extraction format — prompt engineering and response format for agent self-reported confidence; no established pattern in this codebase yet
- **Phase 3:** Approval gate timeout UX — product decision needed on what happens when a critical-path gate times out (auto-deny vs. auto-approve vs. escalate)
- **Phase 4:** Leader research protocol — no existing pattern for orienter/researcher role sequence; needs design from scratch including cost attribution and synthesis timing

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** LiveView `stream/3`, GenServer debounce, signal bus subscriptions — all patterns are directly observable in the existing codebase
- **Phase 2:** HEEX SVG tree rendering follows `DecisionGraphComponent`; OTP `Process.monitor/1` is stdlib; ETS queries follow `Manager.list_agents/1` pattern
- **Phase 4 (happy path):** `TeamSpawn` → `ChildTeamCreated` → `subscribe_to_team` loop already works; the phase adds safety rails on proven infrastructure

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All findings from direct codebase analysis; mix.exs versions confirmed; no speculation |
| Features | HIGH | Existing features verified by reading component source; gap analysis is direct observation |
| Architecture | HIGH | Component boundaries and data flows read from live source files; `workspace_live.ex`, `agent.ex`, `manager.ex`, `agent_loop.ex` all analyzed directly |
| Pitfalls | HIGH | OTP/LiveView pitfalls grounded in direct codebase evidence; CONCERNS.md confirms several as known issues |

**Overall confidence:** HIGH

### Gaps to Address

- **LLM confidence extraction format:** The mechanism is clear (structured output via AgentLoop) but the prompt engineering — how agents self-report confidence 0-100, whether as JSON schema field, a special tag, or a separate tool call — is a design decision not yet made. Address in Phase 3 planning.
- **Performance ceiling under high volume:** At 20+ concurrent agents all streaming simultaneously, the LiveView diff overhead may become measurable. The TeamBroadcaster intermediary design mitigates this, but a load test with 20 concurrent agents should be part of Phase 1 acceptance criteria.
- **Approval gate timeout UX:** The `AskUser` tool times out after 5 minutes with a silent no-answer. For approval gates blocking irreversible actions (file writes, git commits, shell commands), silent timeout behavior is potentially dangerous. A product decision is needed before Phase 3 builds the gate UI.
- **Leader research protocol design:** The orienter/researcher/synthesizer role sequence for the leader-does-research-first pattern is a novel orchestration protocol. No existing pattern in the codebase. Phase 4 planning should treat this as a research-phase candidate.

---

## Sources

### Primary — Direct Codebase Analysis (HIGH confidence)

- `lib/loomkin/agent_loop.ex` — checkpoint mechanism, on_event callbacks, loop pause/resume
- `lib/loomkin/agent_loop/checkpoint.ex` — Checkpoint struct, pause/steer/resume semantics
- `lib/loomkin/tools/ask_user.ex` — Registry-block pattern; template for approval gates
- `lib/loomkin/signals.ex` — Signal bus subscribe/publish/replay API
- `lib/loomkin/signals/team.ex` — All team-domain signal type definitions
- `lib/loomkin/teams/agent.ex` — Pause/resume/steer/queue API; GenServer state machine
- `lib/loomkin/teams/manager.ex` — Spawn, dissolve, sub-team, agent listing APIs; ETS team hierarchy
- `lib/loomkin/teams/supervisor.ex` — OTP supervision tree structure
- `lib/loomkin/teams/comms.ex` — Team communication patterns; signal bus wrapper
- `lib/loomkin/teams/distributed.ex` — DynamicSupervisor / Horde wrapper
- `lib/loomkin_web/live/workspace_live.ex` — LiveView subscriptions, event handlers, 4,714-line monolith
- `lib/loomkin_web/live/team_activity_component.ex` — stream-based activity feed; `stream/3` pattern
- `lib/loomkin_web/live/agent_card_component.ex` — per-agent LiveComponent pattern
- `lib/loomkin_web/live/agent_comms_component.ex` — comms feed rendering
- `lib/loomkin_web/live/ask_user_component.ex` — human question UI component
- `lib/loomkin_web/live/team_dashboard_component.ex` — agent/task display with signal handlers
- `mix.exs` — exact dependency versions
- `.planning/codebase/CONCERNS.md` — known tech debt, fragile areas, missing features

### Secondary — Domain Knowledge (MEDIUM confidence)

- LangGraph human-in-the-loop patterns (interrupt/approve/resume)
- Anthropic agent best practices (checkpoint-based control, confidence escalation)
- Temporal/Prefect approval gate patterns
- Phoenix LiveView rendering model: assigns diffing, `:stream` for append-only lists
- OTP supervision restart behaviors, `Process.monitor` vs supervisor links

---

*Research completed: 2026-03-07*
*Ready for roadmap: yes*
