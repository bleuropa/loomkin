---
phase: 04-task-graph-crash-recovery
plan: 03
subsystem: ui
tags: [liveview, crash-recovery, agent-cards, comms-feed, signals]

requires:
  - phase: 04-task-graph-crash-recovery/04-01
    provides: "AgentWatcher crash/recovery signal infrastructure"
  - phase: 04-task-graph-crash-recovery/04-02
    provides: "TaskGraphComponent SVG DAG with sub-tab routing"
provides:
  - "Agent card crash/recovery/permanently_failed status dot classes and labels"
  - "Crash count badge on agent cards"
  - "Crash/recovery/permanently_failed comms event types with red/amber accents"
  - "Signal handlers in workspace_live for crash/recovery and task graph refresh"
affects: [05-human-intervention-ui]

tech-stack:
  added: []
  patterns:
    - "Process.send_after for recovering->idle status transition after 2s"
    - "Crash count badge using bracket access (@card[:crash_count]) for safe nil handling"

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/agent_card_component.ex
    - lib/loomkin_web/live/agent_comms_component.ex
    - lib/loomkin_web/live/workspace_live.ex

key-decisions:
  - "Reuse card-error class for all crash states (crashed, recovering, permanently_failed)"
  - "2-second Process.send_after delay for recovering->idle transition"

patterns-established:
  - "Crash status visual hierarchy: red pulse (crashed) > amber pulse (recovering) > solid dark red (permanently_failed)"
  - "Bracket access for optional card fields to avoid KeyError"

requirements-completed: [VISB-03, VISB-04]

duration: 8min
completed: 2026-03-07
---

# Phase 4 Plan 3: Crash Recovery UI Wiring Summary

**Agent card crash states (red/amber/dark-red), comms crash events, and workspace_live signal handlers for crash/recovery and task graph refresh**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-08T02:00:00Z
- **Completed:** 2026-03-08T02:09:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Agent cards display :crashed (red pulse), :recovering (amber pulse), and :permanently_failed (solid dark red) status dots with labels
- Crash count badge renders conditionally on agent cards that have crashed during session
- Comms feed supports agent_crashed, agent_recovered, and agent_permanently_failed event types with red/amber accent colors
- workspace_live handles crash/recovery signals, updates agent card statuses, inserts comms events, and auto-transitions recovering->idle after 2s
- Task signals trigger task graph refresh via refresh_ref increment

## Task Commits

Each task was committed atomically:

1. **Task 1: Add crash/recovery status classes to AgentCardComponent and crash event types to AgentCommsComponent** - `e207eef` (feat)
2. **Task 2: Wire crash/recovery and task signals in workspace_live** - `f9e52a2` (feat)
3. **Task 3: Visual verification of task graph and crash recovery ui** - checkpoint:human-verify (user approved, no commit)

## Files Created/Modified
- `lib/loomkin_web/live/agent_card_component.ex` - Added :crashed, :recovering, :permanently_failed status dot classes, labels, card state classes, and crash count badge
- `lib/loomkin_web/live/agent_comms_component.ex` - Added agent_crashed, agent_recovered, agent_permanently_failed type configs with red/amber accents
- `lib/loomkin_web/live/workspace_live.ex` - Added signal handlers for crash/recovery/permanently_failed, clear_recovering timer, task signal graph refresh

## Decisions Made
- Reuse card-error class for all crash states rather than creating new CSS classes
- 2-second Process.send_after delay for recovering->idle transition to give visual feedback

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Pre-existing test failures (3) in unrelated files (google_test.exs, composer_component_test.exs, agent_async_test.exs) - not caused by 04-03 changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 4 complete: task graph, crash recovery infrastructure, and crash recovery UI all wired together
- Ready for Phase 5: Human Intervention UI (pause state, permission gates)
- Blocker noted: permission state machine bug in CONCERNS.md must be addressed in Phase 5

## Self-Check: PASSED

All created/modified files verified present. All task commits (e207eef, f9e52a2) verified in git log.

---
*Phase: 04-task-graph-crash-recovery*
*Completed: 2026-03-07*
