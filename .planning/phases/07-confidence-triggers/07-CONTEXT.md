# Phase 7: Confidence Triggers - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Agents automatically surface questions to the human when uncertain by calling the existing AskUser tool, with rate limiting and batching to prevent interrupt fatigue, and a collective-decide fallback when the human dismisses or doesn't respond. Approval gates (Phase 6) and dynamic tree spawning (Phase 8+) are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Confidence detection mechanism
- The agent explicitly calls AskUser when uncertain — same tool, no new params or flags
- AgentLoop does NOT detect uncertainty from LLM output; the tool call IS the confidence signal
- All team AskUser calls are rate-limited (approval gates use RequestApproval, so they're naturally excluded from the rate limit — no special logic needed)
- Rate limiter state lives in the Teams.Agent GenServer — a `last_asked_at` timestamp field
- Rate limit check happens before the tool task process blocks (intercept at the GenServer level)

### Rate limiting & batching
- Batching IS the rate limit — one pending AskUser card per agent at a time
- If the agent asks again while a card is already open, the new question appends to the existing open card (sequential list: Q1, Q2, Q3 — each with its own answer slot)
- Questions added to an already-open card do not create a second card
- Calls that arrive when the card is open AND within the cooldown window are silently dropped — agent receives a canned tool result: "Rate limit reached — proceeding autonomously"
- 5-minute cooldown starts from when the last question in the batch was answered (not from when the card opened)
- After the cooldown expires, the agent can create a new card with a fresh question

### "Let the team decide" fallback
- Every AskUser card has a "Let the team decide" button alongside the human answer options
- Clicking it triggers CollectiveDecision among the other agents in the team — asking agent's tool call returns with the peer consensus answer
- Timeout (5 minutes, same as AskUser tool's existing default) also routes to CollectiveDecision — same fallback path as explicit dismissal
- The asking agent receives the collective answer and continues — no separate "dismissed" flag needed

### Claude's Discretion
- Exact canned text for rate-limited drops ("proceeding autonomously" is the intent; exact wording flexible)
- CollectiveDecision invocation details (timeout for peer vote, quorum rules)
- Whether a comms feed event is emitted when a question is rate-limited and dropped
- Whether the batched card shows a count badge ("3 pending questions") in the card header

</decisions>

<specifics>
## Specific Ideas

- Cyan/teal is the accent color for confidence questions — already used for channel_message type in the comms feed, so it creates a coherent "agent speaking to human" visual theme distinct from amber (permission hooks) and purple (approval gates)
- The AskUser card expands on the agent card in-place, identical pattern to approval gates (Phase 6) — keeps the question anchored to the agent that asked it
- Agent card status indicator: cyan pulsing dot + "Waiting for you" label — mirrors amber dot for permission hooks and purple dot for approval gates, consistent across all three interrupt types
- Workspace stays fully interactive while a question card is open — only the asking agent's tool task is blocked, same as approval gates
- The batching model (append to open card rather than a separate mechanism) aligns with the success criteria's "single human review card" language while keeping the implementation simple

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AskUser` tool (`lib/loomkin/tools/ask_user.ex`): Existing tool that blocks the tool task process, registers via Registry, and emits `Loomkin.Signals.Team.AskUserQuestion`. Phase 7 reuses this exactly — no new tool or params.
- `CollectiveDecision` tool (`lib/loomkin/tools/collective_decision.ex`): Existing peer consensus tool — used as the fallback when human dismisses or times out.
- `AgentCardComponent` (`lib/loomkin_web/live/agent_card_component.ex`): Has `:approval_pending` expanded panel pattern (Phase 6). AskUser card uses the same in-place expansion with cyan accent instead of purple.
- `AgentCommsComponent` `@type_config`: Cyan already used for `channel_message` type. `ask_user` question type gets cyan styling here.
- `TeamBroadcaster` `@critical_types`: AskUser question signals should be classified as critical for instant delivery (same as approval gate signals from Phase 6).

### Established Patterns
- State machine guards (Phase 5): rate limit check follows the same guard pattern — a function head in `Teams.Agent` that intercepts `:ask_user` tool calls and checks `last_asked_at` before allowing the tool task to proceed.
- `set_status_and_broadcast/2` in Agent GenServer: new `ask_user_pending` status transition goes through here.
- Approval gate timeout via `Process.send_after` (Phase 6): AskUser card timeout uses the same mechanism — `handle_info(:ask_user_timeout, ...)` triggers collective decide fallback.
- `push_activity_event` pattern in workspace_live: AskUser question open/close events emit to comms feed with cyan styling.

### Integration Points
- `lib/loomkin/teams/agent.ex`: Add `last_asked_at` and `pending_ask_user` fields to agent state. Add rate limit guard on AskUser tool interception. Add `handle_info(:ask_user_timeout, ...)` for collective fallback. Add `handle_call(:ask_user_answer, ...)` for multi-question batching — route answer to the specific question's blocked process.
- `lib/loomkin_web/live/workspace_live.ex`: New `handle_event("let_team_decide", ...)` event. New `handle_info` for AskUser question signals. Update AskUserComponent assigns for multi-question batch display.
- `lib/loomkin_web/live/agent_card_component.ex`: Expand `ask_user_pending` state with cyan panel, sequential question list, per-question answer buttons, and "Let the team decide" button.
- `lib/loomkin/signals/team.ex`: Existing `AskUserQuestion` signal reused. Potentially add `AskUserResolved` signal for card close events.
- `lib/loomkin/tools/ask_user.ex`: No changes to tool surface — rate limiting intercepted at the Agent GenServer level before the tool task executes.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 07-confidence-triggers*
*Context gathered: 2026-03-08*
