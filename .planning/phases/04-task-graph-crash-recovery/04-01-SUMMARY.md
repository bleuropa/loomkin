---
phase: 04-task-graph-crash-recovery
plan: 01
subsystem: signals
tags: [genserver, process-monitor, crash-detection, otp, signals]

requires:
  - phase: 02-signal-infrastructure
    provides: "TeamBroadcaster critical signal classification, Jido Signal Bus publish pattern"
provides:
  - "Crashed, Recovered, PermanentlyFailed signal types in Signals.Agent"
  - "AgentWatcher GenServer for process-level crash monitoring"
  - "Critical classification for crash signals in TeamBroadcaster"
  - "Agent :DOWN handler error status differentiation"
affects: [04-task-graph-crash-recovery, 05-intervention-controls]

tech-stack:
  added: []
  patterns: [process-monitor-watch, recovery-check-polling, crash-count-tracking]

key-files:
  created:
    - lib/loomkin/teams/agent_watcher.ex
    - test/loomkin/teams/agent_watcher_test.exs
  modified:
    - lib/loomkin/signals/agent.ex
    - lib/loomkin/teams/team_broadcaster.ex
    - lib/loomkin/teams/agent.ex

key-decisions:
  - "AgentWatcher uses Process.send_after polling (500ms x 5 attempts) for recovery detection rather than registry event hooks"
  - "Crash count tracked per {team_id, agent_name} key across watcher lifetime for monotonic increment"
  - "Agent :DOWN handler sets :error on abnormal exits, :idle on normal/shutdown"

patterns-established:
  - "Process.monitor + :DOWN handler pattern for crash detection GenServers"
  - "Recovery polling via Process.send_after with max attempt cap"

requirements-completed: [VISB-04]

duration: 5min
completed: 2026-03-08
---

# Phase 04 Plan 01: Crash Recovery Signal Infrastructure Summary

**AgentWatcher GenServer monitoring agent processes via Process.monitor with Crashed/Recovered/PermanentlyFailed signal types classified as critical for instant TeamBroadcaster delivery**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-08T02:03:10Z
- **Completed:** 2026-03-08T02:08:30Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Three new signal types (Crashed, Recovered, PermanentlyFailed) added to Signals.Agent following existing Jido.Signal pattern
- AgentWatcher GenServer monitors agent processes, detects crashes, polls for recovery, and publishes PermanentlyFailed after 5 failed attempts
- All three crash signal types classified as critical in TeamBroadcaster for instant delivery bypassing 50ms batch window
- Agent :DOWN handler now differentiates abnormal exits (:error) from normal/shutdown exits (:idle)

## Task Commits

Each task was committed atomically:

1. **Task 1: Define crash signal types and update TeamBroadcaster critical classification** - `5465bd1` (feat)
2. **Task 2 RED: Failing tests for AgentWatcher** - `3bf0148` (test)
3. **Task 2 GREEN: Implement AgentWatcher and update Agent :DOWN handler** - `f01cf82` (feat)

## Files Created/Modified
- `lib/loomkin/signals/agent.ex` - Added Crashed, Recovered, PermanentlyFailed signal type definitions
- `lib/loomkin/teams/agent_watcher.ex` - New GenServer monitoring agent processes via Process.monitor
- `lib/loomkin/teams/team_broadcaster.ex` - Added crash signal types to @critical_types MapSet
- `lib/loomkin/teams/agent.ex` - Updated :DOWN handler to set :error status on abnormal exits
- `test/loomkin/teams/agent_watcher_test.exs` - 4 tests covering crash, recovery, permanently_failed, and crash count

## Decisions Made
- AgentWatcher uses Process.send_after polling (500ms x 5 attempts) for recovery detection rather than registry event hooks
- Crash count tracked per {team_id, agent_name} key across watcher lifetime for monotonic increment
- Agent :DOWN handler sets :error on abnormal exits, :idle on normal/shutdown

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Formatted pre-existing unformatted files**
- **Found during:** Task 1 (commit attempt)
- **Issue:** Pre-commit hook runs mix format --check-formatted on all files; session.ex, google_oauth.ex, and agent.ex had pre-existing formatting issues blocking all commits
- **Fix:** Ran mix format on those files (formatting-only change, no logic changes)
- **Files modified:** lib/loomkin/session/session.ex, lib/loomkin/providers/google_oauth.ex, lib/loomkin/teams/agent.ex
- **Verification:** Pre-commit hook passes
- **Committed in:** 5465bd1 (agent.ex formatting included in Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Formatting-only fix required to unblock commits. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Crash/recovery signal infrastructure ready for UI consumption in 04-02 (agent card crash states)
- AgentWatcher ready to be started as part of team supervision tree when teams are created

---
*Phase: 04-task-graph-crash-recovery*
*Completed: 2026-03-08*

## Self-Check: PASSED
