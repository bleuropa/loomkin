# Phase 6: Approval Gates - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Agents can call a `RequestApproval` tool to pause at critical junctures and surface a human sign-off UI. The approval gate is visually and mechanically distinct from the existing permission hook system (`waiting_permission`). This phase does not include confidence-threshold auto-asks (Phase 7) or sub-team spawn safety gates (Phase 9).

</domain>

<decisions>
## Implementation Decisions

### Approval Card Placement & Design
- Approval gate UI lives on the **agent card** — the card expands in-place to show a full approval panel (question, action buttons, countdown). Card grows vertically, stays in the grid.
- **Purple/violet accent** distinguishes approval gates from permission hooks (amber). Purple border or header strip on the expanded card section.
- Action buttons: **Approve / Deny / Approve w/ Context** — three discrete buttons.
  - Approve: one-click, no text required.
  - Approve w/ Context: reveals a text field for optional guidance to the agent.
  - Deny: offers optional denial reason text field.
- The agent receives the human's text (if any) along with the approval/denial decision in its resumed context.

### Leader Team-Wide Banner
- When an agent with the **existing 'lead' role** hits an approval gate, a persistent banner appears **above the agent card grid** (below the workspace header).
- Banner is **informational only** — workspace stays fully interactive. Other agents keep running, human can still interact with non-leader cards.
- Banner text: something like "Team leader awaiting your approval — team progress depends on this."
- Banner includes the countdown timer, matching the card.
- Banner disappears when the gate is resolved (approved, denied, or timed out).

### Timeout Behavior
- **Default timeout: 5 minutes** — configurable globally (app config) and overridable per-gate via `RequestApproval` args.
- **Visible countdown timer** displayed on the expanded approval card section and on the leader banner (when applicable).
- On timeout: gate **auto-denies**. Agent receives a structured timeout reason:
  `{status: :denied, reason: :timeout, message: "Approval gate timed out after N minutes. Human did not respond."}`.
- The agent can use the timeout reason to decide whether to retry, proceed without approval, or surface an error.

### Approval Context Depth
- The expanded card shows: **agent name, the question text, and one line of 'what the agent is about to do'** (from the RequestApproval context). Clean, scannable — enough to decide without being overwhelmed.
- **`RequestApproval` tool API**: `RequestApproval(question: "...", timeout: 300)` — question is required (shown to human), timeout is optional (defaults to global default).
- **Comms feed events**: approval gate surfaces in the comms feed with purple styling.
  - Request event: "Agent X is requesting approval: [question]"
  - Resolution event: "Approval gate approved/denied by human" or "Approval gate timed out"
- Both open and close events appear in the feed for a full timeline record.

### Claude's Discretion
- Exact purple/violet color value (consistent with brand palette)
- Countdown timer visual design (ring, bar, or text-only)
- Leader banner height, typography, and exact copy
- Positioning of Approve / Deny / Approve w/ Context buttons on the card
- Whether the expanded card uses a collapsible header or always-expanded layout
- Text field placeholder copy for optional Approve w/ Context and Deny reason fields
- Comms event icon/color for approval_gate type vs. other event types

</decisions>

<specifics>
## Specific Ideas

- Permission hook (waiting_permission): amber, inline on card, tool name text + force-pause button. Approval gate: purple, expanded card panel, question text + three action buttons. Visually unambiguous.
- The three-button layout (Approve / Deny / Approve w/ Context) lets the human fast-approve without reading deeply, but rewards careful reading with a richer response option.
- Leader banner with countdown creates appropriate urgency without blocking the UI — human sees the clock is ticking but can still check other agents' status.
- The structured timeout reason `{status: :denied, reason: :timeout, ...}` gives the agent's prompt enough signal to distinguish a deliberate denial from an expired gate, enabling smarter fallback behavior.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AgentCardComponent` (`lib/loomkin_web/live/agent_card_component.ex`): `:approval_pending` state already has amber dot, "Awaiting approval" label, and `agent-card-blocked` class (pre-wired in Phase 5). Needs: purple accent, expanded panel section, action buttons, countdown.
- `AgentCommsComponent` `@type_config`: existing approval comms event type needs to be added (request + resolution events with purple styling).
- `TeamBroadcaster` `@critical_types`: approval gate signals should be classified as critical for instant delivery — pattern established for permission signals.
- Permission hook pattern (`lib/loomkin/permissions/hook.ex`): `pre_tool/2` returns `{:ask, reason}` → agent goes to `:waiting_permission`. Approval gate uses a different mechanism — `RequestApproval` is a tool the agent explicitly calls, not a hook triggered by the permission system.
- `Agent.force_pause/1` (`lib/loomkin/teams/agent.ex`): existing `GenServer.call` pattern for synchronous state transitions — approval gate resolution follows this call pattern.

### Established Patterns
- State machine guards (Phase 5): `:approval_pending` already has a `handle_cast(:request_pause, ...)` guard that queues the pause. Approval gate GenServer handlers follow the same guard pattern.
- `set_status_and_broadcast/2`: single point for status changes + signal emission — approval gate status transitions go through here.
- `push_activity_event` in workspace_live: pattern for pushing comms feed events from workspace handlers — approval gate comms events follow this.
- Critical signal delivery: approval gate opened/resolved signals bypass the 50ms batch window (same as crash signals in Phase 4).
- `Process.send_after` timeout: established pattern for timed state transitions (AgentWatcher uses it for crash recovery). Approval gate timeout uses the same mechanism.

### Integration Points
- `lib/loomkin/teams/agent.ex`: new `handle_call(:approval_response, ...)` handler for approve/deny from workspace. New `handle_info(:approval_timeout, ...)` for auto-deny. `:approval_pending` already exists as a state.
- `lib/loomkin_web/live/workspace_live.ex`: new `handle_event("approve_card_agent", ...)` and `handle_event("deny_card_agent", ...)` events. New `handle_info` for approval gate signals. Leader role detection for banner assign.
- `lib/loomkin_web/live/agent_card_component.ex`: expand `:approval_pending` card with purple panel, question text, three-button layout, countdown timer.
- `lib/loomkin/tools/` (new): `RequestApproval` tool module with `question` (required) and `timeout` (optional, default 5min) params.
- `lib/loomkin/signals/agent.ex`: new `ApprovalRequested` and `ApprovalResolved` signal types.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-approval-gates*
*Context gathered: 2026-03-08*
