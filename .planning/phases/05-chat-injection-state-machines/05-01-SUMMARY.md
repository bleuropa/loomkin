---
phase: 05-chat-injection-state-machines
plan: 01
subsystem: state-machine
tags: [genserver, state-machine, elixir, permission, pause]

requires:
  - phase: 05-00
    provides: test stub files for state machine tests
provides:
  - pause_queued field on Agent struct preventing permission clobbering
  - guarded request_pause handlers by agent status
  - permission_response auto-pause with denial context preservation
  - approval_pending status pre-wired in agent card component
affects: [05-02, 05-03, 06-approval-gates]

tech-stack:
  added: []
  patterns: [status-guarded cast handlers, queued state transitions]

key-files:
  created:
    - test/loomkin/teams/agent_state_machine_test.exs
  modified:
    - lib/loomkin/teams/agent.ex
    - lib/loomkin_web/live/agent_card_component.ex
    - test/loomkin/teams/agent_checkpoint_test.exs

key-decisions:
  - "pause_queued field separate from pause_requested to avoid conflating two distinct mechanisms"
  - "broadcast_team for pause_queued reuses Agent.Status signal with :pause_queued atom status"

patterns-established:
  - "Status-guarded handle_cast: match on %{status: :specific_status} before catch-all"
  - "Queued transitions: set flag, process later in the handler that resolves the blocking state"

requirements-completed: [INTV-04]

duration: 6min
completed: 2026-03-08
---

# Phase 05 Plan 01: Agent State Machine Guards Summary

**Guarded pause/permission state transitions with pause_queued field preventing permission clobbering during pending pause requests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-08T05:19:25Z
- **Completed:** 2026-03-08T05:25:43Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 4

## Accomplishments
- Added `pause_queued` field to Agent struct, preventing `pending_permission` from being overwritten by pause requests
- Guarded `request_pause` by status: `:idle` is no-op, `:waiting_permission`/`:approval_pending` queue the pause
- Modified `permission_response` to check `pause_queued` and auto-transition to `:paused` with denial context preserved
- Pre-wired `:approval_pending` status in agent card component for Phase 6

## Task Commits

Each task was committed atomically (TDD):

1. **RED: Agent state machine guard tests** - `a9a0df8` (test)
2. **GREEN: State machine guard implementation** - `925d58f` (feat)

## Files Created/Modified
- `test/loomkin/teams/agent_state_machine_test.exs` - 9 unit tests for state transition guards
- `lib/loomkin/teams/agent.ex` - pause_queued field, guarded request_pause, permission_response pause check, broadcast_team clause
- `lib/loomkin_web/live/agent_card_component.ex` - approval_pending status in card_state_class, status_dot_class, status_label
- `test/loomkin/teams/agent_checkpoint_test.exs` - Fixed 2 tests to set :working before request_pause

## Decisions Made
- Used separate `pause_queued` field (not reusing `pause_requested`) to keep the two mechanisms distinct
- Reused `Agent.Status` signal with `:pause_queued` atom for broadcasting queued state (no new signal type needed)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed agent_checkpoint_test.exs tests broken by new idle guard**
- **Found during:** GREEN phase verification
- **Issue:** Two existing tests called `request_pause` on idle agents, which is now a no-op
- **Fix:** Added `:sys.replace_state(pid, fn s -> %{s | status: :working} end)` before `request_pause` calls
- **Files modified:** test/loomkin/teams/agent_checkpoint_test.exs
- **Verification:** All 42 tests pass (9 state machine + 33 existing agent tests)
- **Committed in:** 925d58f (part of GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Necessary fix for correctness -- existing tests assumed idle agents accept pause, which is now properly guarded.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- State machine guards in place, safe to build chat injection (05-02) and steer-only resume (05-03)
- approval_pending pre-wired for Phase 6 approval gates
- All existing agent tests continue to pass (zero regressions)

---
*Phase: 05-chat-injection-state-machines*
*Completed: 2026-03-08*

## Self-Check: PASSED
- All created files exist
- All commits verified (a9a0df8, 925d58f)
- pause_queued field confirmed in agent.ex
- approval_pending confirmed in agent_card_component.ex
