---
phase: 4
slug: task-graph-crash-recovery
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in) |
| **Config file** | test/test_helper.exs |
| **Quick run command** | `mix test test/loomkin/teams/tasks_test.exs test/loomkin/teams/agent_watcher_test.exs test/loomkin_web/live/task_graph_component_test.exs -x` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/tasks_test.exs test/loomkin/teams/agent_watcher_test.exs test/loomkin_web/live/task_graph_component_test.exs -x`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | VISB-03 | unit | `mix test test/loomkin_web/live/task_graph_component_test.exs -x` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | VISB-03 | unit | `mix test test/loomkin/teams/tasks_test.exs -x` | ✅ (needs update) | ⬜ pending |
| 04-01-03 | 01 | 1 | VISB-03 | unit | `mix test test/loomkin_web/live/sidebar_panel_component_test.exs -x` | ✅ (needs update) | ⬜ pending |
| 04-02-01 | 02 | 1 | VISB-04 | unit | `mix test test/loomkin/teams/agent_watcher_test.exs -x` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 1 | VISB-04 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | ✅ (needs update) | ⬜ pending |
| 04-02-03 | 02 | 2 | VISB-04 | unit | `mix test test/loomkin_web/live/workspace_live_test.exs -x` | ✅ (needs update) | ⬜ pending |
| 04-02-04 | 02 | 2 | VISB-04 | integration | `mix test test/loomkin/teams/agent_watcher_test.exs -x` | ❌ W0 | ⬜ pending |
| 04-02-05 | 02 | 2 | VISB-04 | unit | `mix test test/loomkin_web/live/agent_comms_component_test.exs -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin_web/live/task_graph_component_test.exs` — stubs for VISB-03 (task graph rendering, edges, state updates)
- [ ] `test/loomkin/teams/agent_watcher_test.exs` — stubs for VISB-04 (crash detection, recovery timing)
- [ ] `test/loomkin_web/live/agent_comms_component_test.exs` — stubs for VISB-04 (crash events in comms feed)

*Existing test files need new test cases but no new file creation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SVG graph visual layout looks correct | VISB-03 | Visual rendering fidelity | Open task graph tab, verify layered layout matches decision graph style |
| Crash animation transitions (red pulse -> amber -> normal) | VISB-04 | CSS animation timing | Kill an agent process, observe card transitions |
| Recovery within 2 seconds perceived by user | VISB-04 | End-to-end timing perception | Kill agent, time visual recovery with stopwatch |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
