---
phase: 07-confidence-triggers
plan: 03
subsystem: ui
tags: [liveview, heex, ask_user, agent_card, batching, phoenix]

# Dependency graph
requires:
  - phase: 07-01
    provides: AskUserTool and ask_user_question/ask_user_answered message bus established
provides:
  - Batched multi-question AskUser panel with cyan styling on agent cards
  - let_team_decide event handler routing collective decisions for all batched questions
  - :ask_user_pending status dot (bg-cyan-500), label ("Waiting for you"), card_state_class ("agent-card-asking")
  - Absolute overlay replaced by appended panel pattern (consistent with approval gate)
affects: [future phases using agent card intervention patterns, 07-confidence-triggers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Appended panel pattern: AskUser panel appended below card content area (not absolute overlay), matching Phase 06 approval gate pattern"
    - "Batched questions: pending_questions is a list on agent card assigns, not a single map"
    - "Test delegates: public _for_test wrappers expose private helper functions without live view rendering overhead"

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/workspace_live.ex
    - lib/loomkin_web/live/agent_card_component.ex
    - test/loomkin_web/live/workspace_live_ask_user_test.exs

key-decisions:
  - "pending_questions list replaces pending_question singular map in agent card assigns to support batching"
  - "let_team_decide event handler uses Enum.reduce to thread socket through handle_collective_decision calls"
  - "Absolute overlay (absolute inset-0 z-10) removed entirely; cyan panel appended below main card content area"
  - "Test delegates (status_dot_class_for_test, status_label_for_test, card_state_class_for_test) added as public functions to avoid live rendering overhead in unit tests"

patterns-established:
  - "Appended panel pattern: intervention panels appended below card content area, not overlaid — consistent across approval gates and AskUser"
  - "Batched question lists: card assigns hold a list of pending items, not a single map"

requirements-completed: [INTV-03]

# Metrics
duration: 9min
completed: 2026-03-08
---

# Phase 7 Plan 03: AskUser Batched Panel Summary

**Cyan batched AskUser panel on agent cards with per-question answer buttons and collective-decision routing via let_team_decide event**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-08T20:10:57Z
- **Completed:** 2026-03-08T20:19:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Replaced the old absolute overlay `pending_question` UI with a new appended panel below card content, matching the Phase 06 approval gate pattern
- Added batched `pending_questions` list to agent card assigns so multiple questions from one agent accumulate rather than overwrite
- `let_team_decide` event handler calls `handle_collective_decision/2` for each pending question belonging to the named agent, then clears the card
- Status dot `bg-cyan-500 animate-pulse`, label "Waiting for you", and `card_state_class` "agent-card-asking" added for `:ask_user_pending`
- Full TDD: 9 tests passing covering all behavior criteria

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: failing tests** - `fc26098` (test)
2. **Task 1+2 GREEN: workspace_live and agent_card_component** - `f4654df` (feat)

_Note: TDD RED commit for tests, single GREEN commit covering both tasks since agent card tests depend on component changes._

## Files Created/Modified

- `lib/loomkin_web/live/workspace_live.ex` - Updated handle_info(:ask_user_question) to batch onto pending_questions list; updated handle_info(:ask_user_answered) to clear list; added let_team_decide event handler; renamed agent card init field from pending_question to pending_questions
- `lib/loomkin_web/live/agent_card_component.ex` - Removed absolute overlay block; added cyan AskUser panel with sequential question list and let_team_decide button; added :ask_user_pending status dot/label/card_state_class; added test delegate functions
- `test/loomkin_web/live/workspace_live_ask_user_test.exs` - Replaced stub tests with full implementations covering batching, let_team_decide, and card component helpers

## Decisions Made

- `pending_questions` list replaces `pending_question` singular map in agent card assigns — batching requires a list for multiple concurrent questions
- `let_team_decide` uses `Enum.reduce` to thread socket through `handle_collective_decision` calls (one per agent question)
- Absolute overlay removed entirely; cyan panel appended below card content area — consistent with Phase 06 approval gate appended panel pattern
- Public `_for_test` delegate functions added to `AgentCardComponent` to expose private helpers for unit testing without LiveView rendering overhead

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Added activity_event_count, activity_known_agents, and buffered_activity_events to test socket**
- **Found during:** Task 1 GREEN (handle_info tests)
- **Issue:** `append_activity_event/2` in workspace_live requires these assigns; test socket built without them caused FunctionClauseError
- **Fix:** Added missing assigns to `build_test_socket/1` helper in test file
- **Files modified:** test/loomkin_web/live/workspace_live_ask_user_test.exs
- **Verification:** All 9 tests pass
- **Committed in:** f4654df (GREEN task commit)

---

**Total deviations:** 1 auto-fixed (missing assigns in test helper)
**Impact on plan:** Auto-fix necessary for tests to compile and run. No scope creep.

## Issues Encountered

None beyond the test socket assigns fix documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- INTV-03 success criteria fully implemented: batched AskUser card with cyan styling surfaces on agent cards when status is :ask_user_pending
- Ready for Phase 07-04 if planned (confidence signal wiring to trigger :ask_user_pending status on agent cards)
- The `let_team_decide` and per-question answer flow are complete; only signal routing from LLM confidence extraction needed to connect end-to-end

---
*Phase: 07-confidence-triggers*
*Completed: 2026-03-08*
