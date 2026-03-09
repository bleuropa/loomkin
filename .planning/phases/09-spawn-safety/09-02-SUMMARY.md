---
phase: 09-spawn-safety
plan: "02"
subsystem: agents
tags: [elixir, genserver, signals, jido, spawn-gate, budget-check]

# Dependency graph
requires:
  - phase: 09-01
    provides: wave 0 stub tests for spawn gate behavior

provides:
  - Loomkin.Signals.Spawn.GateRequested and GateResolved signal structs
  - agent.ex auto_approve_spawns field and three spawn gate handle_calls
  - on_tool_execute TeamSpawn pre-spawn intercept with budget check, gate, auto-approve, timeout
  - TeamBroadcaster @critical_types extended with spawn gate signal type strings

affects:
  - 09-03 (workspace_live spawn gate event handlers)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - spawn gate intercept runs in tool task process (same as AskUser/RequestApproval pattern)
    - GenServer.call from tool task for fresh state reads (auto_approve_spawns, budget)
    - open_spawn_gate cast updates status to approval_pending without blocking GenServer
    - Registry.register {:spawn_gate, gate_id} routes response to blocking tool task

key-files:
  created:
    - lib/loomkin/signals/spawn.ex
    - test/loomkin/teams/agent_spawn_gate_test.exs
  modified:
    - lib/loomkin/teams/agent.ex
    - lib/loomkin/teams/team_broadcaster.ex

key-decisions:
  - "spawn gate intercept runs in tool task (on_tool_execute closure), not in GenServer — same pattern as RequestApproval.run/2"
  - "open_spawn_gate is a cast (not call) to avoid deadlock: tool task sends cast then blocks on receive"
  - "auto_approve_spawns read via GenServer.call(:get_spawn_settings) inside closure for freshness, not from captured state"
  - "budget check queries CostTracker.team_cost_summary/1 synchronously from tool task (safe: separate process from GenServer)"
  - "double-gate guard uses :sys.get_state to check status == :approval_pending before opening spawn gate"
  - "execute_spawn_and_notify/5 publishes GateResolved only when gate_id is non-nil (auto-approve skips this)"

patterns-established:
  - "Spawn gate pattern: cast open → registry register → publish signal → receive block → unregister → publish resolved"
  - "Role cost estimates as @role_cost_estimates module attribute with default 0.20 for unknown roles"
  - "compute_limit_warning checks depth at 80% threshold (floor(2 * 0.8) = 1) and agent count at 80% of 10"

requirements-completed:
  - TREE-03

# Metrics
duration: 22min
completed: 2026-03-09
---

# Phase 09 Plan 02: Spawn Safety Backend Summary

**Spawn gate signal structs, agent budget check + auto-approve handle_calls, and TeamSpawn pre-spawn intercept with human gate, auto-approve, and timeout paths**

## Performance

- **Duration:** 22 min
- **Started:** 2026-03-09T00:55:00Z
- **Completed:** 2026-03-09T01:17:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created `Loomkin.Signals.Spawn.GateRequested` and `GateResolved` signal structs mirroring approval.ex pattern
- Added `auto_approve_spawns: false` to agent defstruct with three new handle_calls: `:get_spawn_settings`, `{:set_auto_approve_spawns, enabled}`, `{:check_spawn_budget, estimated_cost}`
- Implemented full TeamSpawn pre-spawn intercept in `on_tool_execute` — budget exceeded returns immediately, auto-approve skips gate, human gate blocks tool task with receive + timeout auto-deny
- Added `"agent.spawn.gate.requested"` and `"agent.spawn.gate.resolved"` to TeamBroadcaster `@critical_types` for instant LiveView delivery

## Task Commits

Each task was committed atomically:

1. **Task 1: Create spawn signal structs and add auto_approve_spawns to agent defstruct** - `aac92c4` (feat)
2. **Task 2: Implement spawn gate intercept in agent on_tool_execute and update TeamBroadcaster** - `5dc37ac` (feat)

_Note: TDD tasks had test + implementation in single commits per task._

## Files Created/Modified
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/spawn.ex` - GateRequested and GateResolved signal structs
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/agent.ex` - auto_approve_spawns field, three handle_calls, spawn gate intercept helpers
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/team_broadcaster.ex` - @critical_types extended with spawn gate types
- `/Users/vinnymac/Sites/vinnymac/loomkin/test/loomkin/teams/agent_spawn_gate_test.exs` - tests for all three handle_calls

## Decisions Made
- Spawn gate intercept runs in the tool task process (the closure passed to `on_tool_execute`), not in the agent GenServer — mirroring the `RequestApproval.run/2` and `AskUser.run/2` patterns
- `open_spawn_gate` is a `cast` (not a `call`) to avoid deadlock: the tool task sends cast then immediately enters `receive`. A `call` would block waiting for the GenServer reply while the GenServer might be blocked
- `auto_approve_spawns` is read via `GenServer.call(agent_pid, :get_spawn_settings)` inside the closure to get the live value — the closure captures state at loop-build time which could be stale
- Budget check calls `CostTracker.team_cost_summary/1` synchronously from the tool task process (safe because it's a separate process from the GenServer, avoiding re-entrant GenServer calls)
- Double-gate guard uses `:sys.get_state` to inspect agent status before opening a spawn gate, returning an immediate error if status is `:approval_pending`
- `execute_spawn_and_notify/5` receives `gate_id` as `nil` for auto-approve path to skip publishing GateResolved (no gate was opened)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Manager.get_team_meta return type mismatch**
- **Found during:** Task 2 (compute_limit_warning implementation)
- **Issue:** Plan showed `%{depth: d}` match against Manager.get_team_meta, but the function returns `{:ok, map()} | :error` not a bare map. Elixir compiler warned clause would never match
- **Fix:** Changed match to `{:ok, %{depth: d}}`
- **Files modified:** lib/loomkin/teams/agent.ex
- **Verification:** `mix compile` produced no warnings after fix
- **Committed in:** 5dc37ac (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug — wrong pattern match)
**Impact on plan:** Correctness fix required; no scope creep.

## Issues Encountered
- DB sandbox ownership: initial test used `async: true` which caused OwnershipError when agent GenServer accessed CostTracker DB from a different process. Fixed by switching to `async: false` with `Sandbox.checkout` + `Sandbox.mode({:shared, self()})` — same pattern used by poller tests.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Spawn gate backend complete: signal structs, budget check, auto-approve, human gate, timeout path all implemented and tested
- Plan 03 can now wire workspace_live event handlers for `spawn_gate_response` routing, approve/deny actions, and rendering the spawn gate card
