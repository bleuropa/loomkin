# Phase 2: Signal Infrastructure - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a TeamBroadcaster GenServer that sits between the Jido Signal Bus and LiveView, centralizing all signal topic strings into a Topics module, and cleaning up dead subscriptions on process termination. workspace_live.ex stops subscribing to raw Jido signals and exclusively receives batched summaries from TeamBroadcaster.

</domain>

<decisions>
## Implementation Decisions

### Debounce & Batching Strategy
- Priority bypass for critical signals: crashes, permission requests, and ask-user signals skip debouncing and forward instantly
- All other signals (streaming deltas, tool progress, activity updates) batched in 50ms windows
- Batched summaries grouped by signal type (e.g., `{:team_broadcast, %{streaming: [deltas], tools: [complete], activity: [events]}}`) so LiveView handles each group separately
- Fixed 50ms debounce window — no runtime configurability needed
- One TeamBroadcaster GenServer per session (matches workspace_live's one-LiveView-per-session pattern)

### Dual Bus Consolidation
- TeamBroadcaster wraps Jido Signal Bus signals only — Phoenix PubSub session events remain as-is (low-frequency, don't need batching)
- workspace_live subscribes exclusively via TeamBroadcaster — no direct Jido Signal Bus subscriptions from LiveView
- TeamBroadcaster delivers to subscribers via direct process messages (send/2), matching existing Jido Signal Bus delivery pattern
- Emit :telemetry events for batch size and queue depth — no UI work, just instrument for future observability

### Topics Module Scope
- LiveView-facing topics only: covers subscription patterns workspace_live uses (agent.**, team.**, context.**, decision.**, channel.**) and per-team topic generation
- Signal type definitions stay in signals/*.ex where they belong
- Both Jido Signal Bus paths AND Phoenix PubSub topic strings — one module for all topic string generation prevents drift
- Regular functions (e.g., `Topics.team_activity(team_id)`, `Topics.agent_status(agent_id)`) — no macros or compile-time constants

### Subscription Lifecycle
- TeamBroadcaster uses Process.monitor on each subscriber — auto-cleans on {:DOWN, ...} when LiveView dies
- Clean break: old direct Jido subscriptions removed from workspace_live entirely in this phase
- Agent-level GenServers (Loomkin.Teams.Agent) also get unsubscribe cleanup in terminate/2 — per FOUN-03 requirement

### Claude's Discretion
- Internal TeamBroadcaster state structure and timer management
- How to group/classify signal types for priority bypass vs batching
- Exact Jido Signal Bus unsubscribe API usage (may need to check Jido.Signal.Bus docs)
- Test strategy for verifying message queue depth under load
- Whether TeamBroadcaster should be supervised per-session or under a dynamic supervisor

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Loomkin.Signals` module: wraps `Jido.Signal.Bus` with subscribe/publish/replay helpers — TeamBroadcaster can use these internally
- `Loomkin.SignalBus` (named bus): already started in Application supervision tree — TeamBroadcaster subscribes to this
- Signal type definitions in `lib/loomkin/signals/team.ex` and `lib/loomkin/signals/session.ex`: 10+ typed Jido.Signal modules already defined
- `workspace_live.ex` `subscribe_to_team/2` function: tracks subscribed teams in MapSet — pattern to replicate or replace in TeamBroadcaster

### Established Patterns
- Jido Signal Bus uses glob-style path matching (`agent.**`, `team.dissolved`) for subscriptions
- Phoenix PubSub used for session-level events via `Session.subscribe(session_id)`
- LiveComponents receive signals via `handle_info/2` in workspace_live, not directly
- `stream/3` used for comms feed — batched updates must be compatible with stream operations
- Telemetry spans already exist for LLM calls and tool execution (`Loomkin.Telemetry`)

### Integration Points
- `workspace_live.ex` `start_and_subscribe/3`: main subscription setup — must be refactored to use TeamBroadcaster
- `workspace_live.ex` `subscribe_global_signals/1`: subscribes to 5 glob patterns — replace with broadcaster
- `workspace_live.ex` `subscribe_to_team/2`: per-team subscription — replace with broadcaster
- `workspace_live.ex` `terminate/2`: currently only cleans up trust policy — add broadcaster disconnect
- `Loomkin.Teams.Agent`: agent GenServer terminate/2 needs Jido signal unsubscribe
- `Loomkin.Application`: TeamBroadcaster supervisor or dynamic supervisor goes here

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The key constraint is the success criterion: with 10 concurrent streaming agents, workspace_live process message queue length stays under 50 during sustained run.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-signal-infrastructure*
*Context gathered: 2026-03-07*
