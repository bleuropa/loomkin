# Phase 9: Spawn Safety - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Before a leader agent calls the `TeamSpawn` tool, intercept at the tool execution layer, run a budget/limits check, and surface a human approval card showing the planned sub-team composition and estimated cost. Spawning only proceeds after human approval (or auto-approve if enabled and within budget). This phase does not include the leader research protocol (Phase 10).

</domain>

<decisions>
## Implementation Decisions

### Spawn Approval Card Design
- Reuse Phase 6 purple/violet approval gate card design — same expand-in-place pattern, same accent color
- Spawn-specific card content replaces the generic "question" area:
  - Team name (from `team_spawn` params)
  - Planned agent composition: each role with count (e.g., "researcher ×2, coder ×1")
  - Estimated cost: "estimated ~$X" (approximate framing, not exact)
  - Warning line if planned spawn approaches max-agents-per-team or max-nesting-depth limits
- Action buttons: same three-button layout as Phase 6 — **Approve / Deny / Approve w/ Context**
  - Approve: one-click, no text required
  - Approve w/ Context: optional guidance text to the leader
  - Deny: optional denial reason text to the leader
- Leader receives structured denial: `{status: :denied, reason: :human_denied, message: human_text}` — same shape as Phase 6
- **Timeout**: 5-minute default, configurable per spawn via tool args. Auto-denies on timeout with structured reason `{status: :denied, reason: :timeout, ...}`. Same behavior as Phase 6.
- **Auto-approve checkbox on the card**: first spawn gate shows "Auto-approve future spawns" checkbox — toggling it enables auto-approve for the rest of the session

### Budget Threshold & Auto-Block
- Remaining budget = `budget.limit - budget.spent` from `CostTracker.team_cost_summary` (same data the workspace UI already shows)
- If `remaining_budget < estimated_spawn_cost` → spawn is **auto-blocked** without surfacing an approval gate
- Leader receives a tool error result: `{:error, :budget_exceeded, %{remaining: X, estimated: Y}}`
- Leader handles the error in its own context (propose fewer agents, ask human to raise limit, etc.)
- No separate escalation banner for auto-block — tool error is sufficient
- Max-agents-per-team and max-nesting-depth limits: enforced server-side by `Manager` (depth=2 already enforced). When the planned spawn would bring counts to 80%+ of limits, a warning line appears in the spawn approval card. No separate persistent UI warning.

### Cost Estimation
- Fixed per-agent estimates by role — hardcoded constants (e.g., researcher=$0.20, coder=$0.50, reviewer=$0.30, tester=$0.30, lead=$0.50)
- Estimate = sum of per-role estimates for all planned agents
- Displayed as "estimated ~$X" on the approval card
- Used for the budget threshold check (`remaining_budget < estimated_cost` → auto-block)

### Auto-Approve Mode
- Toggle lives on the spawn approval card: "Auto-approve future spawns" checkbox visible on the first spawn gate
- Scope: **session-scoped** — resets on page reload, not persisted to DB
- In auto-approve mode: **budget check still runs**. If within budget → spawn proceeds immediately without showing a gate. If over budget → spawn is auto-blocked (same tool error path as above). Human gate is skipped, safety floor remains.

### Claude's Discretion
- Exact per-role cost estimate values (can be tuned based on typical agent usage)
- Whether to add a "bump limit" suggestion in the budget-exceeded tool error message to the leader
- Countdown timer visual on the spawn gate card (ring, bar, or text — consistent with Phase 6)
- Exact warning threshold for limit warnings (80% suggested above, but exact value is a tuning decision)
- Comms feed event for spawn gate open/resolved (whether to emit one and styling)

</decisions>

<specifics>
## Specific Ideas

- The auto-approve checkbox on the card is a reactive toggle — power users who trust the leader can enable it right when the first gate fires, without navigating to settings first
- The structured timeout/denial reason gives the leader's prompt enough signal to distinguish a deliberate denial from an expired gate — same design intent as Phase 6's structured reason

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RequestApproval` tool (`lib/loomkin/tools/request_approval.ex`): established blocking-tool pattern — spawn safety follows the same on_tool_execute intercept in agent.ex. Phase 9 adds a parallel intercept for `team_spawn`.
- `AgentCardComponent`: `:approval_pending` state already exists with purple dot and expanded panel. Spawn gate reuses the same card state and panel structure, adding spawn-specific fields.
- `CostTracker.team_cost_summary/1`: returns `{total_cost_usd, total_tokens, task_count}`. `roster_budget/1` in workspace_live already wraps this into `%{spent, limit}`.
- `Manager.@default_max_nesting_depth 2`: already enforced in `create_sub_team/3`. Spawn safety checks depth of parent + 1 before intercepting.
- `TeamBroadcaster @critical_types`: spawn gate opened/resolved signals should be classified as critical, same as Phase 6 approval signals.

### Established Patterns
- Phase 6 approval gate: `on_tool_execute` intercept in agent.ex, tool task blocks on `GenServer.call(:approval_response, ...)`, workspace_live handles approve/deny events and publishes resolved signal. Phase 9 follows identical pattern.
- Phase 5 state machine guards: `:approval_pending` already has `handle_cast(:request_pause, ...)` guard. Spawn gate uses same `:approval_pending` state — no new state atom needed.
- `set_status_and_broadcast/2`: single point for status changes + signal emission. Spawn gate transitions go through here.
- `Process.send_after` timeout: established pattern for approval gate auto-deny. Spawn gate timeout uses same mechanism.

### Integration Points
- `lib/loomkin/tools/team_spawn.ex`: Phase 9 does NOT modify the tool itself. Instead, the intercept lives in `agent.ex` `on_tool_execute` — same as `RequestApproval` and `AskUser`.
- `lib/loomkin/teams/agent.ex`: add spawn gate intercept in `on_tool_execute` for `"team_spawn"`. Pre-compute estimated cost from roles params. Check budget via `CostTracker`. If over budget → return error immediately. If within budget → surface gate via signal, block on approval response. Add auto_approve_spawns field to agent state (session-scoped boolean).
- `lib/loomkin_web/live/workspace_live.ex`: new `handle_event("approve_spawn", ...)` and `handle_event("deny_spawn", ...)` events. New `handle_info` for spawn gate signals. New `handle_event("toggle_auto_approve_spawns", ...)` to update agent state.
- `lib/loomkin_web/live/agent_card_component.ex`: extend `:approval_pending` spawn variant — show team name, roles list, estimated cost, optional limit warnings, auto-approve checkbox. Distinguish spawn gate vs. checkpoint gate via a field in pending_approval map (e.g., `type: :spawn_gate | :checkpoint`).
- `lib/loomkin/signals/agent.ex` (or new signals file): `SpawnGateRequested` and `SpawnGateResolved` signal types.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-spawn-safety*
*Context gathered: 2026-03-08*
