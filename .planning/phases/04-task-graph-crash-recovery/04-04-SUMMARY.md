---
phase: 04-task-graph-crash-recovery
plan: 04
subsystem: infra
tags: [genserver, supervision-tree, crash-recovery, otp]

requires:
  - phase: 04-task-graph-crash-recovery
    provides: AgentWatcher GenServer module with crash/recovery/permanently-failed signal publishing

provides:
  - AgentWatcher running as named process in production supervision tree
  - Automatic crash monitoring for all spawned agents via Manager.spawn_agent
  - Fixed agent_async_test regression from 04-01 :DOWN handler change

affects: [05-human-intervention-layer]

tech-stack:
  added: []
  patterns: [named genserver registration via opts for testability]

key-files:
  created: []
  modified:
    - lib/loomkin/teams/supervisor.ex
    - lib/loomkin/teams/manager.ex
    - lib/loomkin/teams/agent_watcher.ex
    - test/loomkin/teams/agent_watcher_test.exs
    - test/loomkin/teams/agent_async_test.exs

key-decisions:
  - "AgentWatcher start_link accepts name: option with __MODULE__ default for named registration while preserving test isolation"

patterns-established:
  - "Named GenServer via opts pattern: accept name: in start_link opts with Keyword.get defaulting to __MODULE__"

requirements-completed: [VISB-03, VISB-04]

duration: 4min
completed: 2026-03-08
---

# Phase 4 Plan 4: Gap Closure - AgentWatcher Wiring Summary

**AgentWatcher wired into Teams.Supervisor as named process with automatic watch registration on every agent spawn, plus agent_async_test :killed status assertion fix**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T02:44:40Z
- **Completed:** 2026-03-08T02:48:40Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- AgentWatcher now starts as a named child of Teams.Supervisor in production
- Every successful Manager.spawn_agent call registers the new agent pid with AgentWatcher for crash monitoring
- Fixed pre-existing test regression where agent_async_test asserted :idle instead of :error for :killed exit

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire AgentWatcher into supervision tree and spawn path** - `04114e1` (feat)
2. **Task 2: Fix agent_async_test.exs regression from 04-01 :DOWN handler change** - `ba05565` (fix)

## Files Created/Modified
- `lib/loomkin/teams/supervisor.ex` - Added AgentWatcher as named child in supervision tree
- `lib/loomkin/teams/manager.ex` - Added AgentWatcher.watch call after successful agent spawn
- `lib/loomkin/teams/agent_watcher.ex` - Updated start_link to accept name: option for named registration
- `test/loomkin/teams/agent_watcher_test.exs` - Fixed test setup to use unique names avoiding conflict with production-registered watcher
- `test/loomkin/teams/agent_async_test.exs` - Changed :idle to :error assertion for :killed exit status

## Decisions Made
- AgentWatcher start_link accepts name: option with __MODULE__ default -- enables named process registration in production while allowing tests to use unique names for isolation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed agent_watcher_test name collision with production watcher**
- **Found during:** Task 1 (wiring AgentWatcher into supervision tree)
- **Issue:** After adding AgentWatcher as a named process to Teams.Supervisor, existing agent_watcher_test.exs failed because start_supervised tried to start a second instance with the same default name
- **Fix:** Changed test setup to use unique atom names via System.unique_integer for each test run
- **Files modified:** test/loomkin/teams/agent_watcher_test.exs
- **Verification:** All 4 agent_watcher_test.exs tests pass
- **Committed in:** 04114e1 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Auto-fix necessary for test isolation after named process registration. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 4 (Task Graph & Crash Recovery) is now fully complete
- All crash detection infrastructure is wired and active in production
- Ready to proceed to Phase 5 (Human Intervention Layer)

---
*Phase: 04-task-graph-crash-recovery*
*Completed: 2026-03-08*
