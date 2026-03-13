---
phase: 06-approval-gates
plan: 05
subsystem: ui
tags: [liveview, heex, phoenix-component, tdd, approval-gate]

# Dependency graph
requires:
  - phase: 06-approval-gates
    provides: leader_approval_pending socket assign set/cleared on approval gate signals
  - phase: 06-approval-gates
    provides: MissionControlPanelComponent with agent card grid layout
provides:
  - Violet banner rendered above agent card grid when @leader_approval_pending is non-nil
  - leader_approval_pending assign passed from workspace_live to MissionControlPanelComponent
  - 3 render tests confirming banner on/off states and countdown timer attribute
affects: [07-confidence-extraction, 08-context-pinning]

# Tech tracking
tech-stack:
  added: []
  patterns: [conditional heex banner with :if guard, phx-hook CountdownTimer deadline-at pattern]

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/workspace_live.ex
    - lib/loomkin_web/live/mission_control_panel_component.ex
    - test/loomkin_web/live/mission_control_panel_component_test.exs

key-decisions:
  - "leader_approval_pending passed as named assign to MissionControlPanelComponent using same pattern as other assigns in the live_component call"
  - "banner inserted before concierge section in the non-focused branch so it always appears above the agent card grid"
  - "countdown timer id scoped to gate_id (leader-banner-timer-{gate_id}) to avoid hook id collisions with per-card timers"

patterns-established:
  - "Team-wide banner pattern: :if={@assign} guard on outer div, violet-950/violet-500 color scheme, animate-pulse dot, phx-hook CountdownTimer with data-deadline-at={started_at + timeout_ms}"

requirements-completed: [INTV-02]

# Metrics
duration: 5min
completed: 2026-03-08
---

# Phase 6 Plan 05: Leader Approval Banner Summary

**Violet team-wide banner above agent card grid showing pending approval question and countdown timer, wired via leader_approval_pending assign from workspace_live to MissionControlPanelComponent**

## Performance

- **Duration:** 5 min (continuation run — Task 1 completed in prior session)
- **Started:** 2026-03-08
- **Completed:** 2026-03-08
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments

- Wired `leader_approval_pending` assign from `workspace_live` into `MissionControlPanelComponent` via `live_component` call
- Rendered conditional violet banner above concierge/agent grid when assign is non-nil, with question text and CountdownTimer hook
- 3 new render tests (banner present, banner absent, deadline-at attribute) pass; no regressions in full suite
- Human visual verification confirmed banner placement and violet styling at http://loom.test:4200

## Task Commits

Each task was committed atomically:

1. **Task 1: wire leader_approval_pending into missioncontrolpanelcomponent and render banner (RED)** - `8e4ae02` (test)
2. **Task 1: wire leader_approval_pending into missioncontrolpanelcomponent and render banner (GREEN)** - `1bb8350` (feat)
3. **Task 2: visual verification of leader approval banner** - checkpoint approved by human (no code changes)

**Plan metadata:** (docs commit — this summary)

_Note: TDD task produced two commits (test → feat). No refactor commit needed._

## Files Created/Modified

- `lib/loomkin_web/live/workspace_live.ex` — added `leader_approval_pending={@leader_approval_pending}` to MissionControlPanelComponent live_component call
- `lib/loomkin_web/live/mission_control_panel_component.ex` — added `leader_approval_pending` to moduledoc assigns list; inserted conditional banner block before concierge section
- `test/loomkin_web/live/mission_control_panel_component_test.exs` — added `describe "leader approval banner"` block with 3 tests

## Decisions Made

- leader_approval_pending passed as named assign to MissionControlPanelComponent using same pattern as other assigns in the live_component call
- Banner inserted before concierge section in the non-focused branch so it always appears above the agent card grid
- Countdown timer id scoped to gate_id (`leader-banner-timer-{gate_id}`) to avoid hook id collisions with per-card timers

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 6 gap closure complete — INTV-02 truth #10 satisfied: leader banner renders when @leader_approval_pending is set
- Phase 6 approval gate feature is fully implemented end-to-end (gate tool, signal plumbing, card ui, countdown timer, team banner)
- Phase 7 (confidence extraction) can proceed independently

---
*Phase: 06-approval-gates*
*Completed: 2026-03-08*
