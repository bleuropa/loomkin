# Technology Stack: Agent Orchestration Visibility & Control

**Project:** Loomkin — multi-agent AI workspace
**Milestone:** Agent orchestration visibility, human-in-the-loop steering, dynamic tree spawning
**Researched:** 2026-03-07
**Overall confidence:** HIGH — based on deep codebase analysis of the existing production system

---

## Research Method

External search tools were not available in this environment. All findings are grounded in:

1. Direct codebase analysis (500+ files read across the existing system)
2. Training-data knowledge of Phoenix LiveView 1.0, OTP 27, and Jido 2.0 — all at HIGH confidence because the existing codebase is running these versions today
3. Signals from CONCERNS.md, which was produced by prior codebase analysis and documents known gaps

This is a **subsequent milestone** on an existing, production-quality system. The research question is not "what stack should we use?" — that is already decided. The research question is "what patterns, additions, and extensions does this specific milestone require within the existing stack?"

---

## Existing Stack Baseline (Do Not Change)

The stack is already chosen and working. This section documents it precisely so the roadmap does not relitigate decided choices.

| Layer | Technology | Version | Status |
|-------|-----------|---------|--------|
| Language | Elixir | 1.18.4 | Locked |
| Runtime | Erlang/OTP | 27 | Locked |
| Web | Phoenix | ~> 1.7 | Locked |
| UI | Phoenix LiveView | ~> 1.0 | Locked |
| CSS | Tailwind | ~> 0.2 | Locked |
| Agent framework | Jido | ~> 2.0 | Locked |
| Signal bus | Jido Signal | ~> 2.0 | Locked |
| Database | PostgreSQL + Ecto | 3.12 | Locked |
| HTTP server | Bandit | ~> 1.6 | Locked |
| Supervision | OTP DynamicSupervisor + Registry | OTP 27 | Locked |
| Distribution layer | Horde (optional) | via Distributed.ex | Already wired |

---

## Recommended Stack for This Milestone

This milestone requires **no new framework-level dependencies**. Every capability needed already exists in the stack. The work is about **pattern application**, not library acquisition.

### Core Framework: Already in Place

**Phoenix LiveView 1.0 with `stream/3` and `send_update/3`**

The `stream/3` primitive is the correct mechanism for the agent-to-agent message feed and the activity timeline. The existing `workspace_live.ex` already uses `stream(:comms_events, [])` and `push_activity_event/2` with `send_update(LoomkinWeb.TeamActivityComponent, ...)`. This is the correct pattern and should be extended, not replaced.

**Why `stream/3` over keeping events in socket assigns:** Stream entries are held in a server-side ref that the client DOM diffing tracks. When a new agent spawns 50 events, only the new entries are diffed and patched — not the entire list. This is critical for a live agent dashboard with potentially hundreds of events per minute. The existing code already applies this correctly for the `comms_events` stream; the new agent message feed should follow the same pattern.

**Confidence:** HIGH — observed directly in working production code.

---

### Signal Routing: Jido Signal Bus (Already in Place)

The `Loomkin.Signals` module wraps `Jido.Signal.Bus` with glob-path subscriptions. The LiveView already subscribes to `agent.**`, `team.**`, `context.**`, `decision.**`, `channel.**`, `collaboration.**`, and `system.**`.

**What this milestone needs from the signal bus:**

1. **New signal type: `agent.peer_message`** — to capture inter-agent messages (currently `PeerMessage` signals exist in `Loomkin.Signals.Collaboration` but are not surfaced distinctly in the UI feed)
2. **New signal type: `team.approval_gate.requested`** — for checkpoint-based approval gates where agents pause for human sign-off
3. **New signal type: `team.approval_gate.resolved`** — when human approves or rejects
4. **New signal type: `agent.confidence.low`** — emitted when an agent's self-assessed confidence falls below threshold, triggering the ask-human flow

The pattern for all new signals follows the existing `Loomkin.Signals.Team` and `Loomkin.Signals.Agent` pattern exactly — `use Jido.Signal, type: "...", schema: [...]`. No library changes needed.

**Confidence:** HIGH — `Loomkin.Signals.Team` was read directly; the pattern is clear and consistent.

---

### Approval Gate Pattern: AgentLoop Checkpoint (Already in Place)

The `Loomkin.AgentLoop.Checkpoint` struct already supports `{:pause, reason}` returns. The `:post_llm` checkpoint fires after LLM response but before tool execution. The `:post_tool` checkpoint fires after each tool.

**What is missing for approval gates:**

The `checkpoint` callback in `AgentLoop` can already pause the loop with `{:pause, reason}`. What does not yet exist is:

1. A **persistent approval gate registry** — when an agent pauses at a checkpoint, the pause needs to be registered somewhere the LiveView can discover it and present it to the human. The `AskUser` tool demonstrates the correct pattern: register with `Registry.register(Loomkin.Teams.AgentRegistry, {:ask_user, question_id}, caller)` and block with `receive do ... after 300_000`.
2. An **approval gate tool** — analogous to `AskUser`, a `RequestApproval` tool that agents call at critical junctures, publishing a `team.approval_gate.requested` signal and blocking with `receive`.
3. A **`LiveView.AskApprovalComponent`** — analogous to `AskUserComponent`, renders pending approval requests with approve/reject buttons.

**Confidence:** HIGH — `AskUser` tool and `AskUserComponent` were read directly; the pattern maps exactly.

---

### Confidence-Threshold Human Triggers

**Pattern needed:** Agent emits `agent.confidence.low` signal when self-confidence drops below threshold; LiveView picks this up and routes it to the ask-human UI.

**Implementation path:**
- Add `:confidence_threshold` option to `AgentLoop.run/2` opts
- In the post-LLM handler, parse a confidence score from the LLM response (ask LLM to rate its own confidence 0-100 in structured output)
- If confidence < threshold, emit signal and call `AskUser` automatically

This requires no new libraries. The LLM structured output parsing already exists via the tool classification path in `AgentLoop`.

**Confidence:** MEDIUM — the mechanism is clear and feasible using existing infrastructure, but the confidence extraction from LLM responses requires design decisions about prompt engineering and response format that are not yet implemented.

---

### Process Tree Visibility: OTP Process Monitoring (BEAM-native)

**Pattern: `Process.monitor/1` + `handle_info({:DOWN, ...})`**

To build a live agent tree view that shows process health:

```elixir
# In WorkspaceLive or a dedicated TreeComponent:
ref = Process.monitor(agent_pid)
# handle_info({:DOWN, ref, :process, pid, reason}, socket)
# -> update UI to show agent as crashed/exited
```

This is pure OTP — no libraries needed. `Process.monitor/1` is in the Erlang stdlib. The existing `Teams.Manager.list_agents/1` already queries `Registry.select/2` on `Loomkin.Teams.AgentRegistry`. The agent tree is reconstructed by:

1. Calling `Manager.list_agents(team_id)` for the root team
2. Calling `Manager.list_sub_teams(team_id)` recursively
3. Each entry has `%{name, pid, role, status, model}`

A tree-structured LiveComponent that monitors each pid will reflect real-time process state without polling.

**What to add:**
- `LoomkinWeb.AgentTreeComponent` — a new LiveComponent that renders the agent hierarchy as a collapsible tree
- Each node shows: agent name, role, status (from Registry metadata), current task, cost so far
- Monitors each agent pid with `Process.monitor/1` so crashes show immediately
- Subscribes to `agent.status` signals for status transitions (already emitted by `Teams.Agent`)

**Confidence:** HIGH — Registry metadata pattern observed in `Teams.Manager.list_agents/1` directly.

---

### Dynamic Tree Spawning: Already Infrastructure-Complete

`Teams.Manager.create_sub_team/3` and `Teams.Manager.spawn_agent/4` already exist. `Teams.Manager.list_sub_teams/1` returns child team IDs recursively. The `Distributed.start_child/1` wrapper handles both local and Horde-distributed spawning.

**What is missing for UI visibility:**

The `team.child.created` signal (`Loomkin.Signals.Team.ChildTeamCreated`) is already defined and published by `Manager.dissolve_team/1`. However, the spawn path in `Manager.create_sub_team/3` does **not** currently publish `ChildTeamCreated`. The LiveView handles it via a `:child_team_available` message from the Session layer.

**Action needed:** Publish `ChildTeamCreated` signal in `Manager.create_sub_team/3` so the UI learns about new child teams immediately from any spawn path, not just the Session-mediated path. This is a one-line addition.

**Leader autonomy for tree depth:** The existing `@default_max_nesting_depth 2` in `Manager` bounds recursive spawning. The leader agent's prompt needs to be extended to reason about complexity and depth independently. The `TeamSpawn` tool already exists and the leader uses it. What is needed is a richer prompt instruction set that guides the leader to evaluate complexity before deciding whether to spawn sub-agents.

**Confidence:** HIGH — all infrastructure was read directly from source.

---

### Human Injection Controls: Already Partially in Place

`WorkspaceLive` already handles:
- `"reply_to_agent"` event → sets `reply_target` → routes next message to specific agent via `Teams.Agent.send_message/2`
- Steering a paused agent via `Teams.Agent.steer/2` (existing API)
- `"ask_user_answer"` event → routes answer back to blocked `AskUser` tool via Registry

**What is missing:**

1. **Pause/redirect command** — no UI element lets the human issue a direct `{:pause}` or `{:cancel}` to a specific agent. `Teams.Agent` has `cancel` GenServer call, but no UI surface for it yet.
2. **Reassign task** — no UI or API to take a task from one agent and hand it to another mid-flight.
3. **Inject into team conversation** — broadcast a human message to the entire team topic so all agents see it as context; this would use `Comms.broadcast/2` but needs a UI entry point.

These are all achievable with existing APIs; the gap is purely in the LiveView event handlers and UI rendering.

**Confidence:** HIGH — event handler code was read directly.

---

## Supporting Libraries: New Additions

Only one new library is worth evaluating for this milestone.

### Optional: `ex_abnf` / structured confidence parsing

**Not recommended.** The LLM confidence parsing should use the existing structured output path (tool calls / JSON extraction) already in `AgentLoop`. Adding a schema-parsing library just for this introduces unnecessary dependency.

### Optional: D3.js or SVG tree rendering for AgentTreeComponent

**Recommendation: Use pure HEEX SVG, not D3.js.**

The existing `DecisionGraphComponent` already renders an SVG DAG in HEEX without JavaScript. The agent tree is a simpler structure (a tree, not a DAG) and can be rendered with HEEX and Tailwind using nested divs with connecting lines. This keeps the stack JavaScript-free for this component and avoids asset pipeline changes.

If the tree grows complex enough that HEEX SVG becomes awkward (e.g., animated edges, drag-and-drop reordering), then D3.js would be the right call. For the MVP tree view, HEEX SVG is sufficient and already proven in this codebase.

**Confidence:** HIGH — `DecisionGraphComponent` was referenced in the architecture docs as using SVG DAG rendering.

---

## What NOT to Use

### Do Not Introduce Phoenix Channels (WebSocket channels)

LiveView already handles all real-time updates via the existing WebSocket connection. Adding a separate Channel layer would create a second WebSocket connection, duplicate subscription management, and split the rendering logic. The Jido Signal Bus + LiveView `handle_info` pattern already solves real-time delivery cleanly.

### Do Not Add a State Management Library (Redux-style, Commanded, etc.)

The CONCERNS.md identifies the monolithic `workspace_live.ex` (4,714 lines) as tech debt, and correctly identifies the fix as LiveComponent extraction — not a state management library. Introducing a state machine library would add a layer without solving the underlying problem. Extract into LiveComponents, following the existing `AgentCardComponent` and `TeamActivityComponent` pattern.

### Do Not Use Phoenix PubSub as the Primary Signal Bus

The codebase uses Phoenix PubSub in exactly one place: `Phoenix.PubSub.subscribe(Loomkin.PubSub, "team:#{team_id}")` for legacy team broadcasts. All new events should use the Jido Signal Bus (`Loomkin.Signals.subscribe/1`) because it provides:
- Glob-path matching (`"agent.**"` catches all agent subtypes)
- Signal replay capability (used for catching up missed decision events on reconnect)
- Typed signal structs with NimbleOptions schema validation
- Causality metadata (team_id, agent_name chain)

**Confidence:** HIGH — both systems are used in the codebase and their distinction is clear from the code.

### Do Not Introduce Absinthe/GraphQL for Real-Time

LiveView with Jido signals already solves the real-time delivery problem. GraphQL subscriptions would add complexity without benefit.

### Do Not Add Horde Unless Clustering Is Enabled

The `Distributed.ex` module already wraps Horde with a feature flag (`Cluster.enabled?/0`). Horde is not listed in `mix.exs` as a standard dependency — it is pulled in only when clustering is configured. This milestone works entirely with local DynamicSupervisor. Do not enable clustering as part of this milestone.

---

## Pattern Catalog: How to Build Each Feature

### Pattern 1: Live Agent-to-Agent Message Stream

**Mechanism:** Jido Signal Bus → `handle_info` in WorkspaceLive → `push_activity_event/2` → `send_update(TeamActivityComponent, new_event: event)`

**New signal type needed:** `Loomkin.Signals.Collaboration.PeerMessage` already exists. Add event type `:peer_message` to `TeamActivityComponent`'s `@type_config` map. No new infrastructure.

**Performance note:** `stream/3` in `TeamActivityComponent` means only new events are diffed. For high-volume teams (10+ agents all active), cap the stream at 500 entries using `stream_insert(socket, :events, event, limit: 500)`.

### Pattern 2: Real-Time Agent Status Dashboard (Agent Cards)

**Mechanism:** `agent.status` signal → `handle_info` in WorkspaceLive → `update(:agent_cards, ...)` → `send_update(AgentCardComponent, card: updated_card)` for the specific card only.

**Already implemented.** The `AgentCardComponent` is already a LiveComponent that renders per-agent. This pattern means only the one card that changed is re-rendered, not the entire roster.

### Pattern 3: Approval Gates (Checkpoint-Based Human Pause)

```
Agent calls RequestApproval tool
  → Tool publishes team.approval_gate.requested signal (with question_id)
  → Tool blocks: receive do {:approval_gate_resolved, ^id, decision} → ...
WorkspaceLive receives signal
  → Adds to pending_approvals list
  → AskApprovalComponent renders
Human clicks approve/reject
  → LiveView sends GenServer.call to resolve
  → Registry lookup finds blocked tool process
  → sends {:approval_gate_resolved, id, :approved | :rejected}
  → Tool unblocks, loop continues
```

This is identical to the `AskUser` tool pattern already in production.

### Pattern 4: Confidence-Threshold Ask-Human Triggers

```
AgentLoop option: confidence_threshold: 70
Post-LLM handler: extract confidence from structured LLM output
  → If confidence < threshold: emit agent.confidence.low signal
  → Call AskUser tool with the uncertain question
  → LiveView shows question in AskUserComponent
  → Human answers, agent continues
```

### Pattern 5: Dynamic Agent Tree View

```elixir
# AgentTreeComponent mounts, subscribes to team.child.created and agent.status
# On mount: build tree from Manager.list_agents + Manager.list_sub_teams (recursive)
# Process.monitor each agent pid
# handle_info({:DOWN, ref, :process, pid, reason}) → mark node as crashed
# Renders as HEEX with nested divs, uses Tailwind for indentation
```

### Pattern 6: Human Direct Commands (Pause, Cancel, Redirect)

Add event handlers to WorkspaceLive:
- `"pause_agent"` → `Teams.Agent.pause(pid)` (send `:pause_requested` to agent GenServer)
- `"cancel_agent"` → `GenServer.call(pid, :cancel, 5_000)` (already implemented in `Teams.Manager.cancel_all_loops/1`)
- `"redirect_agent"` → `Teams.Agent.steer(pid, new_instruction)` (already implemented)

The `steer/2` function in `Teams.Agent` already exists and is used in the reply-to-agent flow.

---

## Key Versions (Confirmed from mix.exs)

| Package | Version Constraint | Notes |
|---------|-------------------|-------|
| phoenix_live_view | ~> 1.0 | `stream/3` available since 0.18, stable in 1.0 |
| jido | ~> 2.0 | Action composition, exec, tool registry |
| jido_signal | ~> 2.0 | Signal bus, pub/sub, replay, glob matching |
| phoenix | ~> 1.7 | PubSub, endpoint, router |
| ecto_sql | ~> 3.12 | Schema, migrations, changesets |
| telemetry | ~> 1.3 | Span events, metrics |

---

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| Existing OTP patterns (DynamicSupervisor, Registry, Process.monitor) | HIGH | Read directly from supervisor.ex, manager.ex, distributed.ex |
| Jido Signal Bus API (subscribe, publish, replay, glob paths) | HIGH | Read directly from signals.ex, comms.ex, team.ex |
| LiveView stream/3 and send_update/3 patterns | HIGH | Read directly from workspace_live.ex and both components |
| AskUser / approval gate pattern | HIGH | Read ask_user.ex and ask_user_component.ex completely |
| AgentLoop checkpoint mechanism | HIGH | Read checkpoint.ex and agent_loop.ex |
| Confidence-threshold LLM extraction | MEDIUM | Mechanism is clear; prompt engineering and response format not yet designed |
| Agent tree SVG rendering | MEDIUM | Decision graph does SVG; tree is simpler, but not yet built |
| New signal type additions | HIGH | Pattern is consistent and well-established in the codebase |

---

## Gaps Requiring Phase-Specific Research

1. **LLM confidence extraction format** — needs a decision on whether agents self-report confidence as structured JSON, a special token, or via a dedicated tool call. This is a prompt engineering question, not a stack question.

2. **Performance of `stream/3` under high agent-message volume** — at 20+ agents all streaming simultaneously, the LiveView diff overhead may become measurable. Recommend a load test with 20 concurrent agents in phase-specific research when building the message feed.

3. **Approval gate timeout UX** — the `AskUser` tool times out after 5 minutes with a silent no-answer. For approval gates blocking critical infrastructure actions, the timeout behavior and UX need explicit design. This is a product decision, not a stack decision.

---

## Sources

All findings are from direct codebase analysis:

- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop.ex` — checkpoint mechanism, on_event callbacks, loop pause/resume
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop/checkpoint.ex` — Checkpoint struct definition
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/tools/ask_user.ex` — Registry-block pattern for human interaction
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals.ex` — Signal bus subscribe/publish/replay API
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/team.ex` — Existing signal type definitions
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/comms.ex` — Team communication patterns
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/manager.ex` — Spawn, dissolve, sub-team, agent listing APIs
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/supervisor.ex` — Supervision tree structure
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/distributed.ex` — DynamicSupervisor / Horde wrapper
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/workspace_live.ex` — LiveView signal subscriptions, event handlers, team subscription patterns
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/team_activity_component.ex` — stream-based activity feed component
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/agent_card_component.ex` — per-agent LiveComponent pattern
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/ask_user_component.ex` — human question UI component
- `/Users/vinnymac/Sites/vinnymac/loomkin/.planning/codebase/CONCERNS.md` — tech debt, fragile areas, missing features
- `/Users/vinnymac/Sites/vinnymac/loomkin/mix.exs` — exact dependency versions

---

*Stack research: 2026-03-07*
