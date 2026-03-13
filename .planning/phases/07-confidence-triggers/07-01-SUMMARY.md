---
phase: 07-confidence-triggers
plan: "01"
subsystem: testing
tags: [elixir, exunit, ask-user, rate-limit, confidence-triggers, tdd-stubs]

# Dependency graph
requires:
  - phase: 06-approval-gates
    provides: approval gate pattern used as model for ask-user confidence flow
provides:
  - Failing test stubs for agent confidence rate-limit guard and AskUser LiveView behaviors
affects:
  - 07-02 (implements rate-limit guard in Agent GenServer)
  - 07-03 (implements WorkspaceLive ask-user card and let_team_decide)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@moduletag :skip used at module level to skip all stubs; @tag :skip redundantly on each test for clarity"
    - "Stub test body: assert false, 'not implemented' as placeholder until Wave 1 implementation"

key-files:
  created:
    - test/loomkin/teams/agent_confidence_test.exs
    - test/loomkin_web/live/workspace_live_ask_user_test.exs
  modified: []

key-decisions:
  - "Commented out unused aliases rather than omitting them — documents intent for Wave 1 implementors"
  - "Kept @tag :skip on each test in addition to @moduletag :skip for explicit per-test readability"

patterns-established:
  - "Wave 0 stub pattern: @moduletag :skip + assert false placeholder, alias commented out"

requirements-completed: [INTV-03]

# Metrics
duration: 4min
completed: 2026-03-08
---

# Phase 7 Plan 01: Confidence Triggers — Wave 0 Test Stubs Summary

**Skipped ExUnit stubs for rate-limit guard (7 cases) and WorkspaceLive ask-user ui (7 cases) enabling Nyquist-compliant Wave 1 implementation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-08T19:57:59Z
- **Completed:** 2026-03-08T20:01:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `test/loomkin/teams/agent_confidence_test.exs` with 7 skipped stubs covering rate limit guard, batch append, drop-on-cooldown, allow-after-cooldown, drop side effects, answer routing, and cooldown semantics
- Created `test/loomkin_web/live/workspace_live_ask_user_test.exs` with 7 skipped stubs covering cyan accent rendering, batched question list, per-question answer buttons, let_team_decide event, batch resolution, status dot, and status label
- Both files compile without errors and exit 0 with 0 failures and 14 combined skipped tests

## Task Commits

Each task was committed atomically:

1. **Task 1: Create agent confidence test stubs** - `9f9b0ef` (test)
2. **Task 2: Create workspace live ask user test stubs** - `42e09b1` (test)

## Files Created/Modified

- `test/loomkin/teams/agent_confidence_test.exs` — 7 @tag :skip stubs for Agent confidence rate-limit behaviors
- `test/loomkin_web/live/workspace_live_ask_user_test.exs` — 7 @tag :skip stubs for WorkspaceLive AskUser card and let_team_decide event behaviors

## Decisions Made

- Commented out unused aliases rather than omitting them — documents intent for Wave 1 implementors without triggering compiler warnings
- Kept `@tag :skip` on each test in addition to `@moduletag :skip` for explicit per-test readability in line with existing stub conventions

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Minor: unused `alias Loomkin.Teams.Agent` triggered a compiler warning. Fixed by commenting out the alias with an explanatory note for Wave 1 implementors.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both stub files are in place; Wave 1 plans (07-02, 07-03) can implement against these contracts and unskip tests as behaviors are built
- No blockers

---
*Phase: 07-confidence-triggers*
*Completed: 2026-03-08*
