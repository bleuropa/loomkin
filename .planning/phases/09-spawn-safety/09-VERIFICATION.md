---
phase: 09-spawn-safety
verified: 2026-03-08T22:05:00Z
status: human_needed
score: 11/12 must-haves verified
human_verification:
  - test: "Trigger a TeamSpawn from a live leader agent and verify the violet spawn gate card appears"
    expected: "Violet card appears on the leader agent with team name, planned roles, estimated cost, countdown timer, and auto-approve checkbox unchecked"
    why_human: "Full end-to-end flow requires a running agent LLM loop and browser rendering — cannot verify HEEx rendering against live signals programmatically"
  - test: "Click Approve on the spawn gate card"
    expected: "Violet panel disappears and the sub-team spawns successfully"
    why_human: "Requires live agent process, real Registry routing, and UI re-render confirmation"
  - test: "Enable auto-approve checkbox, then trigger another spawn"
    expected: "No gate card appears — spawn proceeds immediately without human intervention"
    why_human: "Requires confirming GenServer state toggle propagates through a subsequent tool call intercept"
  - test: "Let a gate time out (reduce timeout to ~10s in iex)"
    expected: "Gate card closes automatically and leader agent receives tool error with reason :timeout"
    why_human: "Requires live runtime — timeout behavior inside a real tool task process"
---

# Phase 9: Spawn Safety Verification Report

**Phase Goal:** Before a leader spawns an expensive sub-tree, a budget check and human approval gate run first — and the gate surfaces the estimated cost so the human can make an informed decision
**Verified:** 2026-03-08T22:05:00Z
**Status:** human_needed (all automated checks passed; visual/end-to-end flow needs human confirmation)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SpawnGateRequested and SpawnGateResolved signal structs exist and publish successfully | VERIFIED | `lib/loomkin/signals/spawn.ex` defines both modules with correct type strings and full schemas |
| 2 | Agent on_tool_execute intercept for TeamSpawn runs budget check before spawning | VERIFIED | `run_spawn_gate_intercept/6` at line 2249 in agent.ex — calls `{:check_spawn_budget, estimated_cost}` before proceeding |
| 3 | Budget exceeded path returns structured tool error without opening a gate | VERIFIED | `{:budget_exceeded, details}` branch at line 2261 calls `AgentLoop.format_tool_result` and returns immediately |
| 4 | Auto-approve path skips the gate and proceeds directly to spawn when within budget | VERIFIED | `if auto_approve do` branch at line 2268 calls `execute_spawn_and_notify` with `gate_id: nil` |
| 5 | Human gate path blocks tool task on receive, publishes SpawnGateRequested, resolves on response | VERIFIED | `run_human_spawn_gate/8` at line 2295: casts gate open, registers Registry key, publishes signal, enters receive block |
| 6 | Spawn gate timeout auto-denies with structured reason after configurable timeout | VERIFIED | `after timeout_ms` clause at line 2390 unregisters, publishes GateResolved(:timeout), returns `{:ok, %{status: :denied, reason: :timeout}}` |
| 7 | Agent state has auto_approve_spawns field and handle_call accessors for budget check and settings | VERIFIED | `auto_approve_spawns: false` in defstruct (line 53); three handle_call clauses at lines 729, 733, 741 |
| 8 | SpawnGateRequested and SpawnGateResolved classified as critical in TeamBroadcaster | VERIFIED | `@critical_types` at lines 33-49 includes `"agent.spawn.gate.requested"` and `"agent.spawn.gate.resolved"` |
| 9 | approve_spawn event sends spawn_gate_response :approved to blocking tool task via Registry | VERIFIED | `handle_event("approve_spawn")` at line 825; calls `send_spawn_gate_response/2` with `%{outcome: :approved}`; 2 tests pass |
| 10 | deny_spawn event sends spawn_gate_response :denied to blocking tool task via Registry | VERIFIED | `handle_event("deny_spawn")` at line 836; calls `send_spawn_gate_response/2` with `%{outcome: :denied, reason: reason}` |
| 11 | toggle_auto_approve_spawns event calls GenServer set_auto_approve_spawns on target agent | VERIFIED | `handle_event("toggle_auto_approve_spawns")` at line 847; `find_agent_pid` then `GenServer.call(pid, {:set_auto_approve_spawns, enabled})` |
| 12 | Agent card renders spawn gate panel with cost info and auto-approve checkbox visible to human | HUMAN | HEEx panel exists in `agent_card_component.ex` with all required fields; human confirmed (2026-03-08 per summary) but canonical browser verification is human-only |

**Score:** 11/12 automated; 1 deferred to human (visual/end-to-end) — human sign-off recorded in 09-04-SUMMARY.md

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/loomkin/signals/spawn.ex` | GateRequested and GateResolved signal structs | VERIFIED | 54 lines; both modules with correct type strings, full schemas, all required fields |
| `test/loomkin/teams/agent_spawn_gate_test.exs` | Budget check, settings, timeout tests | VERIFIED | 159 lines; 8 real tests (not stubs); all pass |
| `test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | Event and signal handler tests | VERIFIED | 273 lines; 10 real tests; all pass |
| `lib/loomkin/teams/agent.ex` | auto_approve_spawns field, handle_calls, intercept | VERIFIED | defstruct field at line 53; 3 handle_call clauses; `run_spawn_gate_intercept`, `run_human_spawn_gate`, `execute_spawn_and_notify` all substantive |
| `lib/loomkin/teams/team_broadcaster.ex` | @critical_types with spawn gate strings | VERIFIED | Both strings present in MapSet at lines 47-48 |
| `lib/loomkin_web/live/workspace_live.ex` | approve_spawn, deny_spawn, toggle event handlers + signal handle_info | VERIFIED | 3 event handlers, 2 signal handle_info clauses, `send_spawn_gate_response/2` helper — all present and wired |
| `lib/loomkin_web/live/agent_card_component.ex` | Spawn gate panel HEEx variant + format_roles/1 | VERIFIED | Panel at lines 456-600 with :if condition on `type == :spawn_gate`; `format_roles/1` at line 804 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `agent.ex` on_tool_execute | `lib/loomkin/signals/spawn.ex` | `GateRequested.new!` in `run_human_spawn_gate` | WIRED | Line 2341: `Loomkin.Signals.Spawn.GateRequested.new!(%{...})` then `Loomkin.Signals.publish(signal)` |
| `agent.ex` handle_call | `Loomkin.Teams.CostTracker` | `CostTracker.team_cost_summary/1` in `:check_spawn_budget` | WIRED | Line 741+: calls `CostTracker.team_cost_summary(state.team_id)` to extract spent cost |
| `agent.ex` on_tool_execute | `Loomkin.Teams.AgentRegistry` | `Registry.register({:spawn_gate, gate_id}, self())` | WIRED | Line 2331: `Registry.register(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id}, self())` |
| `workspace_live.ex` | `Loomkin.Teams.AgentRegistry` | `Registry.lookup({:spawn_gate, gate_id})` in `send_spawn_gate_response/2` | WIRED | Line 4538-4544: `Registry.lookup(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id})` |
| `workspace_live.ex` | agent card assigns | `update_agent_card/3` on SpawnGateRequested signal | WIRED | Line 1221: `update_agent_card(socket, agent_name, %{pending_approval: pending_approval})` |
| `agent_card_component.ex` | `workspace_live approve_spawn` event | `phx-click="approve_spawn"` on Approve button | WIRED | Line 526: `phx-click="approve_spawn"` with `phx-value-gate-id` and `phx-value-agent` |
| `agent_card_component.ex` | `workspace_live toggle_auto_approve_spawns` event | `phx-click="toggle_auto_approve_spawns"` on checkbox | WIRED | Line 513: `phx-click="toggle_auto_approve_spawns"` with `phx-value-agent` and inverted `phx-value-enabled` |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TREE-03 | 09-01, 09-02, 09-03, 09-04 | Pre-spawn budget check and approval gate before spawning expensive sub-trees | SATISFIED | Budget check handle_call in agent.ex; spawn gate intercept in on_tool_execute; human gate with Registry routing; agent card renders estimated cost with approve/deny actions |

No orphaned requirements detected. TREE-03 is the only requirement mapped to Phase 9 in REQUIREMENTS.md and is claimed by all four plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `agent_card_component.ex` | 420-582 | `placeholder=` attributes in textarea elements | Info | HTML textarea placeholder text — not an implementation stub |

No blocker or warning anti-patterns found. All implementation functions are substantive with full logic.

### Human Verification Required

#### 1. Violet spawn gate card appears in browser

**Test:** With a leader agent configured to use TeamSpawn, trigger a sub-team spawn (or simulate via iex: `Loomkin.Signals.publish(Loomkin.Signals.Spawn.GateRequested.new!(%{gate_id: "test", agent_name: "leader", team_id: "t1", team_name: "research-team", roles: [%{"role" => "coder"}], estimated_cost: 0.50}))`)
**Expected:** Violet card appears on the leader agent card showing team name, role composition ("coder x1"), estimated cost (~$0.50), countdown timer running, and auto-approve checkbox unchecked
**Why human:** HEEx rendering, CountdownTimer JS hook behavior, and visual styling cannot be verified programmatically

#### 2. Approve closes the gate

**Test:** Click the "Approve" button on the spawn gate card
**Expected:** Violet panel disappears, sub-team spawns, leader agent resumes execution
**Why human:** Requires confirming Registry message routing reaches the live tool task process and the UI re-renders

#### 3. Auto-approve bypasses gate

**Test:** Check the auto-approve checkbox on a gate, then trigger another spawn
**Expected:** No gate card appears on the second spawn — agent proceeds directly
**Why human:** Requires GenServer state toggle to propagate through a subsequent tool call intercept in a live session

#### 4. Timeout auto-denies gate

**Test:** Reduce spawn gate timeout to ~10s via iex (`Application.put_env(:loomkin, :spawn_gate_timeout_ms, 10_000)`), trigger a spawn, wait without responding
**Expected:** Gate card disappears after 10s and leader receives a tool error with reason :timeout
**Why human:** Timeout behavior inside a real tool task process requires a live runtime

### Summary

Phase 9 achieved its goal. The complete spawn safety pipeline is implemented and tested:

- The spawn signal structs (`lib/loomkin/signals/spawn.ex`) exist with correct type strings and schemas.
- The agent intercept (`run_spawn_gate_intercept` in `agent.ex`) pre-empts TeamSpawn tool execution, runs budget check, checks auto-approve setting, and blocks the tool task in a receive loop for human decisions.
- The critical broadcaster path delivers spawn gate signals to LiveView instantly.
- WorkspaceLive routes approve/deny clicks back to the blocking tool task via Registry and updates agent card state on signal receipt.
- The agent card component renders the violet spawn gate panel with all required fields: team name, role composition, estimated cost, limit warning, countdown, and auto-approve checkbox.

All 37 tests across the three phase test files pass. The human visual checkpoint was recorded as approved in the 09-04-SUMMARY.md (date: 2026-03-08). Formal re-confirmation in a live browser session remains the only outstanding item.

---

_Verified: 2026-03-08T22:05:00Z_
_Verifier: Claude (gsd-verifier)_
