---
phase: 04-task-graph-crash-recovery
verified: 2026-03-08T21:50:00Z
status: human_needed
score: 11/11 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 9/11
  gaps_closed:
    - "AgentWatcher is started as a named child of Teams.Supervisor in production"
    - "Manager.spawn_agent calls AgentWatcher.watch after every successful spawn"
    - "agent_async_test.exs :killed exit assertion corrected from :idle to :error"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Task dependency graph renders correctly in the browser"
    expected: "Graph tab shows Tasks/Decisions sub-tabs; Tasks sub-tab shows SVG DAG when tasks exist; blocking deps = solid arrows, informing = dashed; critical path edges are amber/thick; clicking a node opens detail panel"
    why_human: "SVG rendering correctness, layout quality, and interactive behavior cannot be verified programmatically"
  - test: "Agent crash state visual rendering"
    expected: "When an agent card status is :crashed, shows red pulsing dot with 'Crashed' label and crash count badge; :recovering shows amber pulsing 'Recovering'; :permanently_failed shows solid dark red 'Failed (max restarts)'"
    why_human: "CSS animation behavior and visual hierarchy need browser validation; status transitions over time require live observation"
  - test: "Crash and recovery events in comms feed"
    expected: "agent_crashed events appear with red accent border/background, agent_recovered with amber, agent_permanently_failed with dark red; icons render correctly"
    why_human: "Icon rendering and color fidelity require visual inspection in a live session"
---

# Phase 04: Task Graph & Crash Recovery Verification Report

**Phase Goal:** The task dependency graph shows blocked-by relationships visually, and OTP agent crashes are reflected in the UI as recovered status without a manual page refresh
**Verified:** 2026-03-08T21:50:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure via Plan 04-04

## Gap Closure Summary

Previous verification (2026-03-07) found 3 gaps:

1. AgentWatcher never started in production (supervision tree missing it)
2. Manager.spawn_agent never called AgentWatcher.watch (crash monitoring inert)
3. agent_async_test.exs asserted :idle for :killed exit instead of :error (regression)

Plan 04-04 fixed all three:
- `lib/loomkin/teams/supervisor.ex` line 27: `{Loomkin.Teams.AgentWatcher, name: Loomkin.Teams.AgentWatcher}` added
- `lib/loomkin/teams/manager.ex` line 180: `AgentWatcher.watch(Loomkin.Teams.AgentWatcher, pid, team_id, name)` added
- `lib/loomkin/teams/agent_watcher.ex` line 24: `start_link` now accepts `name:` opt via `Keyword.get`
- `test/loomkin/teams/agent_async_test.exs` line 352: assertion changed to `state.status == :error`
- `test/loomkin/teams/agent_watcher_test.exs` line 21: unique name per test via `System.unique_integer`

Test results: 23/23 agent_async tests pass, 4/4 agent_watcher tests pass, 0 failures.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | When an agent crashes, a Crashed signal is published within milliseconds | VERIFIED | AgentWatcher now started as named process under Teams.Supervisor (supervisor.ex:27); watch called from spawn_agent (manager.ex:180); crash test passes (agent_watcher_test.exs:27) |
| 2 | When the crashed agent restarts, a Recovered signal is published within 2 seconds | VERIFIED | Recovery polling at 500ms intervals confirmed by recovery test (agent_watcher_test.exs:63) passing in 3.7s suite run |
| 3 | When an agent exceeds max restart attempts, a PermanentlyFailed signal is published | VERIFIED | permanently_failed detection test (agent_watcher_test.exs:87) passes with 5-retry logic confirmed |
| 4 | Crash and recovery signals bypass TeamBroadcaster batching for instant delivery | VERIFIED | "agent.crashed", "agent.recovered", "agent.permanently_failed" in @critical_types MapSet at team_broadcaster.ex:41-43 |
| 5 | The sidebar graph tab has sub-tabs for Tasks and Decisions | VERIFIED | render_tab(:graph) has sub-tab bar with :tasks/:decisions buttons at sidebar_panel_component.ex:165-176 |
| 6 | The task graph renders task nodes as an SVG DAG with dependency edges | VERIFIED | TaskGraphComponent renders `<svg>` with positioned nodes and bezier curve edges; 646 lines, substantive |
| 7 | Blocking dependencies show solid arrows; informing dependencies show dashed arrows | VERIFIED | stroke-dasharray "6,4" for :informs only; nil (solid) for :blocks at task_graph_component.ex:521 |
| 8 | Each task node displays title, colored status indicator, and assigned agent name | VERIFIED | task_node renders rect with status colors, status dot circle, title text, owner text |
| 9 | Clicking a task node shows full details in a panel below the graph | VERIFIED | handle_event("select_node") sets selected_node; task_detail rendered when selected_node non-nil |
| 10 | The critical path is visually emphasized | VERIFIED | Critical path edges use stroke-width "3" and #f59e0b amber; verified in test |
| 11 | Crash and recovery events appear in the comms feed as system-level events with distinct colors | VERIFIED | agent_crashed/agent_recovered/agent_permanently_failed in @type_config with red/amber accent colors |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/loomkin/signals/agent.ex` | Crashed, Recovered, PermanentlyFailed signal types | VERIFIED | All three modules defined with correct types and schemas |
| `lib/loomkin/teams/agent_watcher.ex` | GenServer monitoring agent processes, named-registration capable | VERIFIED | 149 lines; start_link accepts name: opt (line 24); watch/4 casts to named process |
| `lib/loomkin/teams/supervisor.ex` | AgentWatcher child in supervision tree | VERIFIED | Line 27: `{Loomkin.Teams.AgentWatcher, name: Loomkin.Teams.AgentWatcher}` |
| `lib/loomkin/teams/manager.ex` | AgentWatcher.watch call after successful spawn | VERIFIED | Line 180: `Loomkin.Teams.AgentWatcher.watch(Loomkin.Teams.AgentWatcher, pid, team_id, name)` |
| `lib/loomkin/teams/team_broadcaster.ex` | Crash signal types in @critical_types | VERIFIED | "agent.crashed", "agent.recovered", "agent.permanently_failed" in MapSet at lines 41-43 |
| `test/loomkin/teams/agent_watcher_test.exs` | Tests for crash/recovery/permanently_failed; isolated from named production process | VERIFIED | 4 tests, unique names via System.unique_integer; all pass |
| `lib/loomkin_web/live/task_graph_component.ex` | SVG DAG renderer for task dependency graph | VERIFIED | 646 lines, full implementation with layout, critical path, click-to-inspect |
| `lib/loomkin_web/live/sidebar_panel_component.ex` | Sub-tab routing between Tasks and Decisions | VERIFIED | graph_sub_tab assign, handle_event("graph_sub_tab"), render_graph_sub_tab dispatcher |
| `lib/loomkin/teams/tasks.ex` | list_with_deps/1 query | VERIFIED | Returns {tasks, deps} tuple at lines 159-174 |
| `test/loomkin_web/live/task_graph_component_test.exs` | Tests for node rendering, edge styles, critical path | VERIFIED | 7 tests across 5 describe blocks, all passing |
| `lib/loomkin_web/live/agent_card_component.ex` | Crashed/recovering/permanently_failed status dot classes and labels | VERIFIED | status_dot_class(:crashed) = "bg-red-500 animate-pulse", crash count badge present |
| `lib/loomkin_web/live/agent_comms_component.ex` | Crash/recovery event type configs with red/amber accents | VERIFIED | agent_crashed, agent_recovered, agent_permanently_failed in @type_config |
| `lib/loomkin_web/live/workspace_live.ex` | Signal handlers for crash/recovery/task signals | VERIFIED | handle_info for agent.crashed/recovered/permanently_failed at lines 1035-1110; refresh_task_graph via send_update |
| `test/loomkin/teams/agent_async_test.exs` | Corrected :killed exit assertion | VERIFIED | Line 352: `assert state.status == :error`; 23 tests, 0 failures |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `supervisor.ex` | `agent_watcher.ex` | Child spec in init/1 | VERIFIED | Line 27: named child spec present; process starts on application boot |
| `manager.ex` | `agent_watcher.ex` | AgentWatcher.watch/4 in spawn_agent success branch | VERIFIED | Line 180: called with named process atom, pid, team_id, name |
| `agent_watcher.ex` | `signals/agent.ex` | Publishes Crashed/Recovered/PermanentlyFailed on :DOWN | VERIFIED | `Signals.Agent.Crashed.new!` at line 77; test confirms signals publish |
| `team_broadcaster.ex` | "agent.crashed" | @critical_types MapSet membership | VERIFIED | "agent.crashed" in @critical_types |
| `workspace_live.ex` | `agent_card_component.ex` | handle_info for crash signals updates card status | VERIFIED | update_card_status(agent_name, :crashed) at line 1052 |
| `workspace_live.ex` | `task_graph_component.ex` | Task signals increment refresh_ref | VERIFIED | send_update(LoomkinWeb.TaskGraphComponent, id: "task-graph", refresh_ref: ref) at lines 3013-3018 |
| `agent_comms_component.ex` | comms_stream | Crash events inserted into comms stream | VERIFIED | stream_insert(:comms_events, event) at lines 1055, 1082, 1104 |
| `sidebar_panel_component.ex` | `task_graph_component.ex` | render_graph_sub_tab(:tasks) renders TaskGraphComponent | VERIFIED | live_component module={LoomkinWeb.TaskGraphComponent} at line 190 |
| `task_graph_component.ex` | `lib/loomkin/teams/tasks.ex` | Tasks.list_with_deps/1 called on mount/refresh | VERIFIED | Tasks.list_with_deps(team_id) at line 94 |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| VISB-03 | 04-02, 04-03 | Task dependency graph displays blocked-by relationships visually | SATISFIED | TaskGraphComponent renders SVG DAG with solid/dashed arrows; sidebar sub-tabs; 7 component tests pass |
| VISB-04 | 04-01, 04-03, 04-04 | OTP crash recovery reflected in UI — crashed agent restarts show recovered status with no manual refresh | SATISFIED | Full signal pipeline wired: AgentWatcher in supervisor (supervisor.ex:27) + watch call in spawn_agent (manager.ex:180) + TeamBroadcaster critical bypass + workspace_live signal handlers + agent card UI states. 4 watcher tests pass. |

### Anti-Patterns Found

None. No TODOs, placeholders, stub returns, or orphaned modules found in phase 4 files after gap closure.

### Human Verification Required

#### 1. Task Dependency Graph Visual Rendering

**Test:** Start dev server at http://loom.test:4200, open a session with tasks, click the Graph tab in the sidebar, then click the Tasks sub-tab.
**Expected:** SVG DAG renders showing task nodes with colored status indicators; dependency arrows are solid for :blocks and dashed for :informs; critical path edges are thicker and amber (#f59e0b); clicking a task node opens a detail panel below the graph showing title, status, and assigned agent.
**Why human:** SVG layout quality, arrow styling visibility, and interactive click-to-inspect behavior require browser observation.

#### 2. Agent Card Crash State Visuals

**Test:** Trigger an agent crash in a live session (or simulate via IEx `Process.exit(pid, :kill)`); observe the agent card in the workspace sidebar.
**Expected:** Card shows red pulsing dot (bg-red-500 animate-pulse) labeled "Crashed" with a crash count badge (e.g., "1x crashed"); after supervisor restart, transitions to amber pulsing "Recovering"; then returns to normal status — all without a manual page refresh.
**Why human:** CSS animation (animate-pulse), color rendering, and timed status transitions via LiveView push require live browser observation.

#### 3. Comms Feed Crash Events

**Test:** Observe the comms/activity feed during and after an agent crash/recovery cycle.
**Expected:** agent_crashed event appears with red accent border/background; agent_recovered with amber accent; agent_permanently_failed (after 5 failed recovery checks, ~2.5s) with dark red accent; event icons render correctly.
**Why human:** Accent color fidelity, icon rendering, and real-time stream insertion require visual inspection in a live session.

---

_Verified: 2026-03-08T21:50:00Z_
_Verifier: Claude (gsd-verifier)_
