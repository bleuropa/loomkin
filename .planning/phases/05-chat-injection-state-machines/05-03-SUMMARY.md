---
phase: 05-chat-injection-state-machines
plan: 03
subsystem: ui
tags: [liveview, agent-card, state-machine, force-pause, comms-feed]

requires:
  - phase: 05-01
    provides: "State machine guards, pause_queued field, pause/permission safety"
  - phase: 05-02
    provides: "Broadcast messaging, inject_broadcast, composer indicator"
provides:
  - "Distinct agent card controls for pause vs permission states"
  - "Dual state indicator (permission-pending + pause queued badge)"
  - "Force-pause escape hatch cancelling pending permissions"
  - "Steer-only resume flow (mandatory guidance)"
  - "State transition comms event types (agent_paused, permission_requested, agent_force_paused)"
  - "Extended agent_status signal with pause_queued and previous_status metadata"
affects: [06-approval-gates, 07-confidence-extraction]

tech-stack:
  added: []
  patterns:
    - "4-tuple agent_status signal with metadata map for extensible status broadcasts"
    - "Force-pause GenServer.call pattern for synchronous state transition"

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/agent_card_component.ex
    - lib/loomkin_web/live/workspace_live.ex
    - lib/loomkin_web/live/agent_comms_component.ex
    - lib/loomkin/teams/agent.ex
    - lib/loomkin/signals/agent.ex
    - test/loomkin_web/live/agent_card_component_test.exs

key-decisions:
  - "Resume button removed in favor of steer-only flow requiring mandatory guidance text"
  - "Force-pause uses GenServer.call (synchronous) to ensure immediate transition"
  - "set_status_and_broadcast extended to 4-tuple signal with metadata map for backwards compatibility"

patterns-established:
  - "4-tuple signal pattern: {:agent_status, name, status, metadata} with fallback 3-tuple handler"
  - "Force-pause as escape hatch: cancels pending permission, saves cancelled context in paused_state"

requirements-completed: [INTV-04, INTV-01]

duration: 7min
completed: 2026-03-08
---

# Phase 5 Plan 3: Agent Card UI for State Machine Guards Summary

**Distinct agent card controls with force-pause escape hatch, dual state indicator, steer-only resume, and state transition comms events**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-08T05:30:00Z
- **Completed:** 2026-03-08T05:37:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Agent cards now show distinct controls: pause for working, force-pause for waiting_permission, steer-only for paused
- Dual state indicator shows "pause queued" badge when permission is pending and pause has been requested
- Force-pause cancels pending permission with confirmation dialog and saves cancelled context
- State transition comms events (agent_paused, permission_requested, agent_force_paused) render with themed styling
- set_status_and_broadcast propagates pause_queued and previous_status via extended 4-tuple signal
- Human visual verification confirmed the full Phase 5 feature set works end-to-end

## Task Commits

Each task was committed atomically:

1. **Task 1: Agent card distinct controls, dual indicator, and force-pause** - `c96bc39` (feat)
2. **Task 2: Visual verification of complete Phase 5 feature set** - checkpoint:human-verify (approved)

## Files Created/Modified
- `lib/loomkin/teams/agent.ex` - Force-pause GenServer.call API, extended set_status_and_broadcast with metadata
- `lib/loomkin/signals/agent.ex` - Updated signal struct for extended status broadcasts
- `lib/loomkin_web/live/agent_card_component.ex` - Distinct controls, dual indicator, last-transition hint, approval_pending status
- `lib/loomkin_web/live/agent_comms_component.ex` - agent_paused, permission_requested, agent_force_paused event types
- `lib/loomkin_web/live/workspace_live.ex` - Force-pause handler, resume-to-steer redirect, 4-tuple signal handler
- `test/loomkin_web/live/agent_card_component_test.exs` - Component tests for card state rendering

## Decisions Made
- Resume button removed; only steer button for paused agents (mandatory guidance per locked decision)
- Force-pause uses synchronous GenServer.call to ensure immediate state transition
- Extended set_status_and_broadcast to emit 4-tuple signal {:agent_status, name, status, %{previous_status, pause_queued}} with backwards-compatible 3-tuple fallback handler

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Complete Phase 5 feature set delivered: state machine guards, broadcast messaging, and UI controls
- Ready for Phase 6 (Approval Gates) which builds on the permission state machine foundation
- Force-pause and steer-only patterns established for reuse in approval gate UI

## Self-Check: PASSED

All 6 modified files verified present on disk. Commit c96bc39 verified in git log.

---
*Phase: 05-chat-injection-state-machines*
*Completed: 2026-03-08*
