---
phase: 09-spawn-safety
plan: "03"
subsystem: liveview-event-routing
tags: [spawn-gate, liveview, registry, signal-handling, tdd]
dependency_graph:
  requires: ["09-02"]
  provides: ["workspace-spawn-gate-event-handlers", "workspace-spawn-gate-signal-handlers"]
  affects: ["agent-card-ui", "spawn-gate-loop"]
tech_stack:
  added: []
  patterns: ["registry-routing", "pending-approval-map", "update-agent-card"]
key_files:
  created: []
  modified:
    - lib/loomkin_web/live/workspace_live.ex
    - test/loomkin_web/live/workspace_live_spawn_gate_test.exs
decisions:
  - "approve_spawn uses gate_id param key (not gate-id with dash) matching plan spec"
  - "toggle_auto_approve_spawns uses find_agent_pid with nil team_id (falls back to cached_agents lookup)"
  - "spawn gate signal handlers do not emit comms events (unlike approval gate) — plan did not require them"
metrics:
  duration: 8
  completed: "2026-03-09"
  tasks: 2
  files: 2
---

# Phase 9 Plan 03: Spawn Gate LiveView Event and Signal Handlers Summary

**One-liner:** workspace_live.ex spawn gate bridge — approve/deny/toggle event handlers and SpawnGateRequested/Resolved signal handlers routing human decisions back to blocking tool tasks via Registry.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add approve_spawn, deny_spawn, toggle_auto_approve_spawns event handlers | aee8f9b | workspace_live.ex, workspace_live_spawn_gate_test.exs |
| 2 | Add SpawnGateRequested and SpawnGateResolved signal handle_info clauses | aee8f9b | workspace_live.ex |

## What Was Built

### Event Handlers (workspace_live.ex)

Three new `handle_event` clauses mirroring the Phase 6 approval gate pattern:

- `approve_spawn` — receives `gate_id` and optional `context`, calls `send_spawn_gate_response/2` with `%{outcome: :approved, context: context}`
- `deny_spawn` — receives `gate_id` and optional `reason`, calls `send_spawn_gate_response/2` with `%{outcome: :denied, reason: reason}`
- `toggle_auto_approve_spawns` — receives `agent` name and `enabled` string, uses `find_agent_pid/3` to locate the agent GenServer and calls `GenServer.call(pid, {:set_auto_approve_spawns, enabled})`

Private helper `send_spawn_gate_response/2` mirrors `send_approval_response/2` but uses the `{:spawn_gate, gate_id}` registry key and `{:spawn_gate_response, gate_id, decision}` message format.

### Signal Handlers (workspace_live.ex)

Two new `handle_info` clauses for Jido.Signal matching:

- `"agent.spawn.gate.requested"` — extracts gate_id, agent_name, team_name, roles, estimated_cost, limit_warning, timeout_ms, auto_approve_spawns from sig.data; builds `pending_approval` map with `type: :spawn_gate`; calls `update_agent_card/3`
- `"agent.spawn.gate.resolved"` — extracts agent_name; calls `update_agent_card/3` to set `pending_approval: nil`

### Tests (workspace_live_spawn_gate_test.exs)

Replaced Wave 0 stubs with fully implemented tests:
- 2 tests for approve_spawn (routing + noreply when no pid)
- 2 tests for deny_spawn (routing with reason + noreply when no pid)
- 2 tests for toggle_auto_approve_spawns (enabled/disabled, graceful noreply)
- 2 tests for SpawnGateRequested (pending_approval set with correct shape)
- 2 tests for SpawnGateResolved (pending_approval cleared, graceful noreply for unknown agent)

All 10 tests pass.

## Decisions Made

- `approve_spawn` uses `gate_id` (underscore) as param key per plan spec, matching test stubs
- `toggle_auto_approve_spawns` uses `find_agent_pid(socket, agent_name, nil)` — nil team_id falls back to `cached_agents` lookup, consistent with other handlers that take agent name without team-id
- Signal handlers do not emit comms events (the plan did not specify them and the approval gate comms events are not part of the spawn gate requirements per the task behavior spec)

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check

- [x] workspace_live.ex modified with event and signal handlers
- [x] workspace_live_spawn_gate_test.exs stubs replaced with real tests
- [x] All 10 tests pass
- [x] Full test suite: 1996 tests, 2 failures (pre-existing Google auth env failures), 4 skipped

## Self-Check: PASSED
