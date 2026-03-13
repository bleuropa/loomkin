---
phase: 01-monolith-extraction
plan: "04"
subsystem: loomkin_web
tags: [livecomponent, mission-control, agent-cards, extraction]
dependency_graph:
  requires:
    - lib/loomkin_web/live/agent_card_component.ex
    - lib/loomkin_web/live/agent_comms_component.ex
  provides:
    - lib/loomkin_web/live/mission_control_panel_component.ex
  affects:
    - lib/loomkin_web/live/workspace_live.ex
tech_stack:
  added: []
  patterns:
    - LiveComponent event forwarding via send(self(), {:mission_control_event, event, params})
    - comms_stream nil-guard for test isolation
key_files:
  created:
    - lib/loomkin_web/live/mission_control_panel_component.ex
    - test/loomkin_web/live/mission_control_panel_component_test.exs
  modified: []
decisions:
  - comms_stream guarded with nil check so render_component tests do not require a live process
  - build_card/2 helper in test module provides minimal valid AgentCardComponent-compatible struct
metrics:
  duration: ~15 minutes
  completed: 2026-03-07
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 1 Plan 04: Mission Control Panel Component Summary

**One-liner:** Extracted left-panel agent grid, ghost cards, and comms feed from workspace_live.ex into MissionControlPanelComponent LiveComponent with full event forwarding.

## What Was Built

`LoomkinWeb.MissionControlPanelComponent` is a standalone LiveComponent that renders the left column of the mission control view:

- Focused single-agent view (back button + AgentCardComponent) when `focused_agent` is set
- Concierge card(s) at top in normal view
- Worker agent grid with `grid-cols-2 lg:grid-cols-3` layout
- Waiting state and no-session state divs when no agents are present
- Ghost card buttons for dormant kin (enabled kin not yet spawned)
- Comms feed via `AgentCommsComponent.comms_feed` (nil-guarded for test safety)

All interactive events (`focus_card_agent`, `unfocus_agent`, `reply_to_card_agent`, `pause_card_agent`, `resume_card_agent`, `steer_card_agent`, `open_queue_drawer`, `spawn_dormant_kin`) are forwarded to the parent WorkspaceLive via:
```elixir
send(self(), {:mission_control_event, event, params})
```

Private helpers copied from workspace_live.ex: `render_ghost_cards/1`, `card_grid_cols/1`, `any_agents_active?/2`, `kin_potency_color/1`, `format_agent_role/1`.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 - Create component | 4e2a61a | feat(01-04): add mission control panel livecomponent |
| 2 - Write tests | 938218c | test(01-04): add render tests for mission control panel component |

## Test Results

5 tests, 0 failures covering:
1. Renders waiting state when no agents (C/O ghost avatars + status text)
2. Renders Kin section header
3. Shows agent count badge with worker card names
4. Renders dormant kin ghost cards
5. Renders focused agent back button ("All agents")

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test card structs missing required fields for AgentCardComponent**
- **Found during:** Task 2
- **Issue:** `render_component` renders nested `live_component` children including `AgentCardComponent`, which accesses `card.latest_content`, `card.last_tool`, `card.pending_question`, `card.current_task` via pattern matching in `update/2` and `render/1`. Initial test card structs lacked these fields causing `KeyError`.
- **Fix:** Added `build_card/2` helper in test module with all required fields set to nil defaults; added nil guard in plan's suggested `comms_stream` approach.
- **Files modified:** test/loomkin_web/live/mission_control_panel_component_test.exs
- **Commit:** 938218c

**2. [Rule 1 - Bug] HTML entity escaping in waiting state assertion**
- **Found during:** Task 2
- **Issue:** `assert html =~ "Concierge &amp; Orienter ready"` — `render_component` returns raw HTML with `&` escaped as `&amp;`, but asserting the literal ampersand string also works if split across the entity. Changed assertion to match substrings that don't cross the entity boundary.
- **Fix:** Split assertion into `html =~ "Concierge"` and `html =~ "Orienter ready"`.
- **Files modified:** test/loomkin_web/live/mission_control_panel_component_test.exs
- **Commit:** 938218c

## Self-Check: PASSED

- lib/loomkin_web/live/mission_control_panel_component.ex: FOUND
- test/loomkin_web/live/mission_control_panel_component_test.exs: FOUND
- commit 4e2a61a: FOUND
- commit 938218c: FOUND
