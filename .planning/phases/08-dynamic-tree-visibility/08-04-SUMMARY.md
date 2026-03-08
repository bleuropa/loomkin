---
phase: 08-dynamic-tree-visibility
plan: "04"
subsystem: ui
tags: [liveview, team-tree, pubsub, elixir, recursion]

# Dependency graph
requires:
  - phase: 08-02
    provides: ChildTeamCreated signal with team_id, parent_team_id, team_name, depth fields
  - phase: 08-01
    provides: stub test file with four named test cases to implement
provides:
  - team_tree map assign replacing flat child_teams list in workspace_live
  - team_names map assign for signal-derived name lookup without Manager round-trips
  - collect_descendants/2 recursive helper for dissolution walks
  - remove_from_tree/2 helper for pruning tree map entries
  - recursive unsubscribe on Dissolved signal for all descendants
affects:
  - 08-05 (TeamTreeComponent will render from team_tree and team_names assigns)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - team_tree map keyed by parent_team_id with child_team_id list values
    - team_names map keyed by child_team_id from signal payload (no Manager round-trip)
    - collect_descendants/2 + remove_from_tree/2 recursive private helpers
    - 4-tuple handle_info dispatch for child_team_created carrying parent and name

key-files:
  created: []
  modified:
    - lib/loomkin_web/live/workspace_live.ex
    - test/loomkin_web/live/workspace_live_tree_test.exs

key-decisions:
  - "handle_info :child_team_created arity changed to 4-tuple {child_id, parent_id, team_name} — signal handler extracts all three fields from sig.data"
  - "team_names starts empty on reconnect — names repopulate on next ChildTeamCreated signal; Plan 05 falls back to short_id when name absent"
  - "toolbar select bridged with Map.values(@team_tree) |> List.flatten() for flat id list — Plan 05 replaces entire select with TeamTreeComponent"
  - "ConnCase used in tree tests (not ExUnit.Case) because child_team_created handler calls refresh_roster which hits DB"

patterns-established:
  - "4-tuple handle_info dispatch: signal handler extracts parent_team_id and team_name then forwards to tuple handler"
  - "recursive tree walk: collect_descendants collects all descendants before any unsubscribe; remove_from_tree called via Enum.reduce for full cleanup"

requirements-completed: [TREE-01]

# Metrics
duration: 15min
completed: 2026-03-08
---

# Phase 08 Plan 04: Dynamic Tree Visibility — workspace_live Tree Assign Migration Summary

**workspace_live migrated from flat child_teams list to team_tree map with team_names, recursive dissolution walk unsubscribing all descendants**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-08T18:10:00Z
- **Completed:** 2026-03-08T18:25:00Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- Replaced `child_teams: []` list assign with `team_tree: %{}` map assign keyed by parent_team_id
- Added `team_names: %{}` assign populated from ChildTeamCreated signal payload — no Manager round-trip at render time
- Updated signal handler to extract parent_team_id and team_name and forward as 4-tuple to handle_info
- Dissolved handler now walks collect_descendants/2, unsubscribes all descendants, prunes both team_tree and team_names
- Added `collect_descendants/2` and `remove_from_tree/2` private helpers
- mount reconnect path rebuilds team_tree from Manager.list_sub_teams/1 (team_names left empty, repopulates on signals)
- Toolbar select temporarily bridged to use team_tree (full TeamTreeComponent replacement in Plan 05)
- All 4 tree tests pass, no regressions in full suite (2 pre-existing Google auth failures excluded)

## Task Commits

1. **Task 1 RED: add failing tree tests** - `efbbe7c` (test)
2. **Task 1 GREEN: implement team_tree and team_names assigns** - `b5e1bd6` (feat)

## Files Created/Modified

- `lib/loomkin_web/live/workspace_live.ex` — team_tree/team_names assigns, updated handlers, two private helpers, toolbar bridge
- `test/loomkin_web/live/workspace_live_tree_test.exs` — four tests covering mount default, child creation, dissolution walk, and subscription

## Decisions Made

- handle_info `:child_team_created` changed from 2-tuple to 4-tuple `{child_id, parent_id, team_name}` — signal handler at team.child.created now extracts all three fields from sig.data before delegating
- `team_names` starts empty on reconnect path — repopulates on first ChildTeamCreated signal, and Plan 05 TeamTreeComponent falls back to `short_id/1` when name is absent
- Used ConnCase (not ExUnit.Case) for tree tests because the child_team_created handler calls refresh_roster which requires DB sandbox ownership
- Toolbar `@child_teams != []` guard replaced with `@team_tree != %{}` with `Map.values(@team_tree) |> List.flatten()` for flat child id list as temporary bridge

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- First test run hit DBConnection.OwnershipError from refresh_roster/1 DB query in child_team_created handler. Fixed by switching test module from `ExUnit.Case, async: true` to `LoomkinWeb.ConnCase` (which sets up Ecto sandbox). Tests pass without any DB mocking needed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- team_tree and team_names assigns are in place and populated from signal data
- Plan 05 can render TeamTreeComponent directly from @team_tree and @team_names assigns without Manager ETS lookups
- Toolbar select is a temporary bridge — Plan 05 replaces it with the full tree component

---
*Phase: 08-dynamic-tree-visibility*
*Completed: 2026-03-08*
