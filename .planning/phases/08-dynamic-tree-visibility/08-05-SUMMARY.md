---
phase: 08-dynamic-tree-visibility
plan: "05"
subsystem: ui
tags: [liveview, live_component, team-tree, popover, toolbar]

# Dependency graph
requires:
  - phase: 08-04
    provides: team_tree and team_names assigns in workspace_live; ChildTeamCreated signal pipeline

provides:
  - TeamTreeComponent LiveComponent with popover dropdown showing indented team hierarchy
  - toolbar "Teams" trigger button hidden by default, auto-appears when sub-team exists
  - active team highlighting per row with agent counts derived from roster assign
  - old <select> team switcher removed from workspace_live toolbar
  - handle_info({:switch_team, team_id}) delegation in workspace_live

affects:
  - 09-agent-visibility
  - workspace_live
  - team hierarchy ui

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ModelSelectorComponent popover pattern reused (mount open: false, toggle/close events, phx-click-away)
    - send(self(), {:event, data}) from LiveComponent to parent LiveView for team switching
    - depth-based inline padding-left style for tree indentation

key-files:
  created:
    - lib/loomkin_web/live/team_tree_component.ex
    - test/loomkin_web/live/team_tree_component_test.exs
  modified:
    - lib/loomkin_web/live/workspace_live.ex

key-decisions:
  - "TeamTreeComponent hidden via :if={@team_tree != %{}} on outer div — no render at all when no sub-teams exist"
  - "agent_counts derived at render time via compute_agent_counts(roster) helper — no additional assign needed"
  - "depth rendered up to 2 levels (root, child, grandchild) matching Manager's maximum hierarchy depth"
  - "team_names falls back to short_id/1 when name absent (reconnect path before next ChildTeamCreated signal)"

patterns-established:
  - "Live component popover: mount open: false, toggle_tree/close_tree events, phx-click-away on dropdown div"
  - "Parent delegation: send(self(), {:switch_team, team_id}) from component handle_event, handle_info in workspace_live delegates to event handler"

requirements-completed:
  - TREE-01

# Metrics
duration: ~25min
completed: 2026-03-08
---

# Phase 08 Plan 05: TeamTreeComponent Summary

**TeamTreeComponent LiveComponent with indented popover dropdown replaces the old toolbar <select>, auto-hidden until a sub-team exists, showing live team names and agent counts**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-08T22:17:47Z
- **Completed:** 2026-03-08T22:45:00Z
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments

- Created TeamTreeComponent LiveComponent with TDD (RED → GREEN) — popover open/close, select_team delegation, tree rendering with depth-based indentation
- Wired TeamTreeComponent into workspace_live toolbar replacing the old `<select>` team switcher; added `compute_agent_counts/1` helper
- Human visually verified: Teams trigger hidden with no sub-teams, appears on spawn, popover opens/closes, node switching works, old select is gone

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TeamTreeComponent (RED)** - `9b2e51c` (test)
2. **Task 1: Create TeamTreeComponent (GREEN)** - `6a94a46` (feat)
3. **Task 2: Wire TeamTreeComponent into toolbar** - `0ef8ba9` (feat)
4. **Task 3: Visual verification** - human-approved (no code changes)

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified

- `lib/loomkin_web/live/team_tree_component.ex` - New LiveComponent: mount, update, toggle_tree/close_tree/select_team events, team_row/1 function component, short_id/1 fallback
- `test/loomkin_web/live/team_tree_component_test.exs` - Tests for hidden-when-empty, toggle open, close_tree, select_team → switch_team message to parent
- `lib/loomkin_web/live/workspace_live.ex` - Old `<select>` removed; TeamTreeComponent live_component rendered in toolbar; compute_agent_counts/1 private helper added; handle_info({:switch_team, team_id}) delegation added

## Decisions Made

- `compute_agent_counts(roster)` derives `%{team_id => count}` at render time from existing roster assign — no new assign, no Manager round-trip
- Depth capped at 2 levels (root → child → grandchild) matching Manager hierarchy constraint from Phase 08-03
- Outer div uses `:if={@team_tree != %{}}` — component produces zero DOM output when tree is empty (trigger hidden by default)
- `team_names` fallback to `short_id/1` when name absent handles reconnect path before next ChildTeamCreated signal (established in 08-04 decision)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 08 (dynamic tree visibility) is fully complete — tree data pipeline, ChildTeamCreated signal, team_tree/team_names assigns, and TeamTreeComponent ui all ship together
- Phase 09 (agent visibility) can proceed; workspace_live toolbar is clean, no child_teams references remain
- No blockers

---
*Phase: 08-dynamic-tree-visibility*
*Completed: 2026-03-08*
