# Phase 5: Chat Injection & State Machines - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

A human can broadcast a message to the entire team conversation (not just reply-to-agent), and agent pause state is strictly separated from permission-pending state via typed state machine guards. No approval gates (Phase 6), no confidence triggers (Phase 7) — this phase adds broadcast messaging and fixes the state clobbering bug.

</domain>

<decisions>
## Implementation Decisions

### Broadcast Delivery
- Messages delivered at each agent's next checkpoint (between tool calls / iterations) — non-disruptive, agents finish current work first
- All agents receive the broadcast including paused and crashed ones — paused agents see it when resumed, crashed agents see it if they recover
- Root team only — broadcast does not cascade to sub-teams. Keeps the message scoped to the team the human is viewing
- Claude's discretion on whether agents emit acknowledgment events in the comms feed

### Composer Mode Switch
- Context-dependent default: solo sessions default to Architect pipeline; team sessions default to broadcast. Automatically adapts to the session type
- Agent count badge near the broadcast indicator (e.g., "5 agents") — quick confirmation of who will receive
- Claude's discretion on the visual indicator style (reply bar vs button mode) and mode switching interaction (@ button vs keyboard shortcut)

### State Machine Design
- Guards on key transitions — keep the current flat-atom status approach but add guard clauses on dangerous transitions (e.g., can't overwrite permission_pending with paused)
- When pause is requested during pending_permission: queue the pause. After permission is resolved (approved or denied), the agent automatically transitions to paused
- If permission is denied with a queued pause: agent still pauses (does not resume to handle denial). The denial context is available when the human eventually resumes with guidance
- Dual indicator on agent card when both states active: permission-pending as primary status + small "pause queued" badge
- Pause and permission controls are different buttons entirely — pause shows a pause icon button; permission shows approve/deny buttons with tool call details. Completely separate control surfaces
- Resuming a paused agent requires providing guidance text — mandatory, not optional. Forces the human to redirect the agent
- Pre-wire `:approval_pending` as a recognized state with guards now (for Phase 6), even though the approval gate UI comes later
- Only key state transitions emit signals to comms feed (paused, permission requested, error) — skip noise like idle->working
- Last-transition hint on agent card: shows current state plus small "from: working" context. One level of history without full timeline
- Force-pause escape hatch: a "force pause" option that warns "This will cancel the pending permission" and requires confirmation. Power-user emergency override

### Claude's Discretion
- Broadcast acknowledgment behavior (whether agents emit receipt events)
- Composer broadcast indicator visual design (reply bar pattern vs button mode)
- Mode switching UX (@ button picker vs keyboard shortcut)
- Force-pause confirmation UX design
- Which specific state transitions are "key" enough to emit signals
- Exact guard clause implementation (function heads vs explicit checks)

</decisions>

<specifics>
## Specific Ideas

- The state clobbering bug is explicitly called out in STATE.md: "pending_permission can be overwritten — must be fixed in Phase 5"
- Broadcast should feel like an operator announcement — the human speaking to the whole team, not just one agent
- The dual indicator (permission + queued pause) ensures the human's intent is always visible even during complex state interactions
- Force-pause exists for emergencies but should feel like a deliberate override, not a casual action

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ComposerComponent` (`lib/loomkin_web/live/composer_component.ex`): Already has "Entire Kin" option in agent picker that clears `reply_target`. Needs to route to broadcast instead of Architect pipeline for team sessions
- `AgentCommsComponent`: Has `@type_config` map defining color/icon per event type — new `:human_broadcast`, `:human_reply`, and state transition event types added here
- `TeamBroadcaster`: Batching GenServer with critical signal bypass — broadcast messages should be classified as critical for prompt delivery
- `Agent.send_message/2`: Existing per-agent message delivery — broadcast iterates over team agents calling this
- `Agent.steer/2` and `Agent.resume/2`: Existing pause/resume flow — resume already accepts guidance text

### Established Patterns
- `set_status_and_broadcast/2` in Agent GenServer: single point for status changes — guards added here
- `pending_permission` is a separate field from `status` in Agent state — the two need coordinated transition logic
- Composer events forwarded via `send(self(), {:composer_event, event, params})` — new broadcast event follows this pattern
- Comms events have `:type`, agent name, content structure — state transition events follow the same shape
- `select_reply_target` with `"team"` already exists but clears reply_target — needs to set a broadcast mode flag instead

### Integration Points
- `workspace_live.ex` `handle_event("send_message", ...)`: Currently has 3 branches (steer, reply, Architect) — needs a 4th branch for team broadcast
- `workspace_live.ex` `handle_info({:composer_event, "select_reply_target", %{"agent" => "team"}})`: Currently clears reply_target — needs to set broadcast mode
- `Agent` GenServer `handle_call` clauses for `:pause` and permission resolution — guards added here to prevent clobbering
- `AgentCardComponent` render: needs distinct control surfaces for pause vs permission states
- `AgentCommsComponent` `@type_config`: new event types for broadcast, state transitions

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-chat-injection-state-machines*
*Context gathered: 2026-03-07*
