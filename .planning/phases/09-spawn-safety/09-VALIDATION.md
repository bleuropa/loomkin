---
phase: 9
slug: spawn-safety
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/teams/agent_spawn_gate_test.exs test/loomkin_web/live/workspace_live_spawn_gate_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/agent_spawn_gate_test.exs test/loomkin_web/live/workspace_live_spawn_gate_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 9-01-01 | 01 | 0 | TREE-03 | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-01-02 | 01 | 0 | TREE-03 | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-01-03 | 01 | 0 | TREE-03 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs` | ✅ | ⬜ pending |
| 9-02-01 | 02 | 1 | TREE-03 | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-02-02 | 02 | 1 | TREE-03 | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-02-03 | 02 | 1 | TREE-03 | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-03-01 | 03 | 2 | TREE-03 | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-03-02 | 03 | 2 | TREE-03 | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-03-03 | 03 | 2 | TREE-03 | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |
| 9-04-01 | 04 | 3 | TREE-03 | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/teams/agent_spawn_gate_test.exs` — stubs for budget check, gate open/close, auto-approve, timeout (TREE-03)
- [ ] `test/loomkin_web/live/workspace_live_spawn_gate_test.exs` — stubs for handle_event approve/deny/toggle and handle_info SpawnGateRequested/Resolved (TREE-03)
- [ ] Modify `test/loomkin/teams/team_broadcaster_test.exs` — add assertions for spawn gate signal types in `@critical_types`

*Test style reference: Follow `test/loomkin_web/live/workspace_live_approval_test.exs` — `ExUnit.Case, async: true`, build minimal Phoenix.LiveView.Socket directly in helpers, use `Registry.register` to simulate blocking tool task process, use `assert_receive` for message routing assertions.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Spawn approval card renders correctly in browser with role list, estimated cost, countdown timer | TREE-03 | Visual UI verification | Open workspace, trigger a team_spawn tool call, verify the violet approval card appears with team name, roles, estimated cost, and countdown |
| Auto-approve checkbox reflects current state after toggle | TREE-03 | Visual state verification | Toggle auto-approve, trigger another spawn, verify no gate appears and spawn proceeds |
| Budget-exceeded auto-block delivers tool error to leader without showing UI gate | TREE-03 | E2E verification with mock cost | Set a low budget, trigger spawn that would exceed it, verify no gate appears and leader receives error |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
