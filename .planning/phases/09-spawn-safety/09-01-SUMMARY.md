---
phase: 09-spawn-safety
plan: "01"
subsystem: spawn-gate
tags: [tdd, wave-0, stubs, spawn-safety]
dependency_graph:
  requires: []
  provides:
    - test/loomkin/teams/agent_spawn_gate_test.exs
    - test/loomkin_web/live/workspace_live_spawn_gate_test.exs
    - spawn gate critical_types assertions in team_broadcaster_test.exs
  affects:
    - Plans 02-03 must satisfy all stubs in these files
tech_stack:
  added: []
  patterns:
    - wave-0 stub pattern (@moduletag :skip + @tag :skip per test)
    - flunk("not implemented") placeholder for complex stubs
key_files:
  created:
    - test/loomkin/teams/agent_spawn_gate_test.exs
    - test/loomkin_web/live/workspace_live_spawn_gate_test.exs
  modified:
    - test/loomkin/teams/team_broadcaster_test.exs
decisions:
  - "[Phase 09-01]: wave 0 stub pattern reused exactly from phases 7/8 — @moduletag :skip at module level, @tag :skip per test"
  - "[Phase 09-01]: spawn gate signal types agent.spawn.gate.requested and agent.spawn.gate.resolved will be classified as critical in TeamBroadcaster (Plan 02)"
metrics:
  duration_seconds: 99
  completed_date: "2026-03-09"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
---

# Phase 9 Plan 01: Spawn Gate Test Stubs Summary

Wave 0 failing test stubs for all spawn safety behaviors — two new test files plus broadcaster critical_types assertions, defining the full contract for Plans 02-03.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create agent_spawn_gate_test.exs and workspace_live_spawn_gate_test.exs stubs | 6ebddbe | test/loomkin/teams/agent_spawn_gate_test.exs, test/loomkin_web/live/workspace_live_spawn_gate_test.exs |
| 2 | Add spawn gate critical_types assertions to team_broadcaster_test.exs | b15f1bb | test/loomkin/teams/team_broadcaster_test.exs |

## What Was Built

### agent_spawn_gate_test.exs

Five wave-0 stubs covering the full spawn gate GenServer contract:

1. `check_spawn_budget` returns `{:budget_exceeded, %{remaining: _, estimated: _}}` when over budget
2. `check_spawn_budget` returns `:ok` when budget is sufficient
3. `get_spawn_settings` returns `%{auto_approve_spawns: false}` by default
4. `set_auto_approve_spawns` sets flag and is readable via `get_spawn_settings`
5. Spawn gate timeout auto-denies after 50ms (fast test path)

### workspace_live_spawn_gate_test.exs

Five wave-0 stubs covering the LiveView event and signal handler contract:

1. `approve_spawn` event routes `{:spawn_gate_response, gate_id, %{outcome: :approved}}` to Registry-registered blocking process
2. `deny_spawn` event routes `{:spawn_gate_response, gate_id, %{outcome: :denied, reason: _}}` to Registry-registered blocking process
3. `toggle_auto_approve_spawns` event with `enabled: "true"` calls `set_auto_approve_spawns` on agent GenServer
4. `handle_info` for `SpawnGateRequested` signal sets `pending_approval` on matching agent card
5. `handle_info` for `SpawnGateResolved` signal clears `pending_approval` from matching agent card

### team_broadcaster_test.exs additions

Two new failing assertions in a `spawn gate critical classification` describe block:
- `agent.spawn.gate.requested` must be classified as critical (currently fails — not in @critical_types)
- `agent.spawn.gate.resolved` must be classified as critical (currently fails — not in @critical_types)

## Verification Results

```
29 tests, 2 failures, 10 skipped
```

- 10 skipped: wave-0 stubs in the two new files (expected)
- 2 failures: spawn gate types not yet in `@critical_types` (expected — Plan 02 adds them)
- 17 passing: all pre-existing broadcaster tests remain green

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED
