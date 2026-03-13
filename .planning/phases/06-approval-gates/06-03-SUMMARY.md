---
phase: 06-approval-gates
plan: "03"
subsystem: liveview
tags: [liveview, approval-gates, registry, signals, leader-banner, comms-feed]

# Dependency graph
requires:
  - phase: 06-02
    provides: RequestApproval tool, Approval.Requested/Resolved signals, AgentRegistry routing under {:approval_gate, gate_id}

provides:
  - handle_event approve_card_agent routes :approved decision to blocking tool task via Registry
  - handle_event deny_card_agent routes :denied decision, clears leader banner when gate_id matches
  - send_approval_response/2 helper mirrors send_ask_user_answer/2 pattern
  - handle_info agent.approval.requested sets pending_approval on card, sets leader_approval_pending for :lead role
  - handle_info agent.approval.resolved clears pending_approval from card, clears leader_approval_pending
  - approval_gate_requested and approval_gate_resolved comms feed events

affects:
  - 06-04 (agent card ui — renders pending_approval card state, sends approve/deny events that reach these handlers)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - approval-gate routing: handle_event calls send_approval_response/2 which does Registry.lookup({:approval_gate, gate_id}) and send/2 — mirrors AskUser pattern exactly
    - leader banner toggle: check role == :lead after updating card to set/clear leader_approval_pending assign
    - comms event streaming: stream_insert(:comms_events, event) with update(:comms_event_count) for approval gate open/close

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/workspace_live.ex
    - test/loomkin_web/live/workspace_live_approval_test.exs

key-decisions:
  - "approve handler clears leader_approval_pending via deny only — approve does not clear it (user clicked approve, gate remains for resolved signal to clear)"
  - "pending_approval cleared in both handle_event AND handle_info resolved to cover timeout path without user interaction"
  - "comms events streamed directly via stream_insert rather than through forward_to_cards_and_comms to keep approval types isolated"

patterns-established:
  - "approval-gate LiveView plumbing: event -> send_approval_response -> Registry -> tool task; signal -> handle_info -> card update + leader banner"

requirements-completed:
  - INTV-02

# Metrics
duration: 8min
completed: 2026-03-08
---

# Phase 06 Plan 03: Workspace Live Approval Gate Plumbing Summary

**Approval gate event handlers and signal handlers wired into workspace_live.ex — approve/deny buttons route decisions via Registry, ApprovalRequested/Resolved signals update card state, leader banner, and comms feed**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-08T18:51:03Z
- **Completed:** 2026-03-08T18:58:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `handle_event("approve_card_agent")` and `handle_event("deny_card_agent")` clauses that route approval decisions to the blocking RequestApproval tool task via `Registry.lookup({:approval_gate, gate_id})` — mirrors the existing AskUser pattern exactly
- Added `defp send_approval_response/2` helper adjacent to `send_ask_user_answer/2` for consistency
- Empty string normalization: both `context` (approve) and `reason` (deny) are normalized from `""` to `nil`
- `deny_card_agent` clears `leader_approval_pending` when the resolved `gate_id` matches
- Added `handle_info` for `agent.approval.requested` signal: sets `pending_approval` on the agent card, conditionally sets `leader_approval_pending` when agent role is `:lead`, streams `approval_gate_requested` comms event
- Added `handle_info` for `agent.approval.resolved` signal: clears `pending_approval` from card, clears `leader_approval_pending` when gate_id matches, streams `approval_gate_resolved` comms event (with outcome-specific label including `:timeout`)
- Replaced stub `flunk("not implemented")` tests with 15 real passing tests covering all behaviors

## Task Commits

1. **Task 1: approve/deny handle_event and send_approval_response helper** - `71e71a0` (feat)
2. **Task 2: handle_info for approval signals, leader banner, comms events** - `4fb1da9` (feat)

## Files Created/Modified

- `lib/loomkin_web/live/workspace_live.ex` — two handle_event clauses, two handle_info clauses, send_approval_response/2 helper
- `test/loomkin_web/live/workspace_live_approval_test.exs` — 15 real tests replacing stub flunks

## Decisions Made

- `deny_card_agent` clears `leader_approval_pending` in the event handler (immediate user action path); `approve_card_agent` does not — the resolved signal will clear it on the signal path
- `pending_approval` is cleared in both event handlers (user action) AND in the resolved signal handler (timeout/signal path) to cover both flows
- Comms events streamed directly with `stream_insert` rather than routed through `forward_to_cards_and_comms` — approval types are not in `@comms_event_types` and the direct path avoids adding them to a general routing list

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added `cached_agents: []` to test socket builder**
- **Found during:** Task 1 (test RED run)
- **Issue:** `update_agent_card/3` calls `Map.get(cards, name, default_agent_card(name, socket))` which eagerly evaluates `default_agent_card/2` even when the card exists; that function accesses `socket.assigns.cached_agents` which was missing from the test socket
- **Fix:** Added `cached_agents: []` to the test socket assigns in `build_test_socket/1`
- **Files modified:** test/loomkin_web/live/workspace_live_approval_test.exs
- **Committed in:** 71e71a0 (Task 1 commit, test file)

**2. [Rule 2 - Test quality] Rewrote test helper to avoid `Phoenix.LiveView.assign/2`**
- **Found during:** Task 1 (test RED run)
- **Issue:** `Phoenix.LiveView.assign/2` is not a public function; the state machine tests put all assigns directly in the socket struct
- **Fix:** All test variants use `opts` keyword list in `build_test_socket/1` to inject role, gate_id, and leader_approval_pending directly into the socket assigns map
- **Files modified:** test/loomkin_web/live/workspace_live_approval_test.exs
- **Committed in:** 71e71a0 (Task 1 commit, test file)

---

**Total deviations:** 2 auto-fixed (both test infrastructure corrections)
**Impact on plan:** No scope creep. Implementation matched plan spec exactly.

## Issues Encountered

Pre-existing test failures (4 in full suite run) verified to be environmental: Google OAuth config present in dev env overrides test expectations; CostDashboardLive timing flakiness. None introduced by this plan.

## Next Phase Readiness

- All LiveView plumbing complete: approve/deny events route to Registry, approval signals update card state and leader banner, comms feed logs gate open/close
- Plan 04 (agent card ui) can now render the `pending_approval` card state and emit `approve_card_agent`/`deny_card_agent` events that will be handled by these clauses

---
*Phase: 06-approval-gates*
*Completed: 2026-03-08*

## Self-Check: PASSED

- lib/loomkin_web/live/workspace_live.ex: FOUND
- test/loomkin_web/live/workspace_live_approval_test.exs: FOUND
- .planning/phases/06-approval-gates/06-03-SUMMARY.md: FOUND
- commit 71e71a0: FOUND
- commit 4fb1da9: FOUND
- handle_event approve_card_agent at line 718: FOUND
- handle_event deny_card_agent at line 735: FOUND
- send_approval_response/2 at line 4319: FOUND
- handle_info agent.approval.requested at line 998: FOUND
- handle_info agent.approval.resolved at line 1046: FOUND
- 15 tests, 0 failures: CONFIRMED
