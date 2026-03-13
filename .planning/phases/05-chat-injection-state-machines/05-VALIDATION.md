---
phase: 5
slug: chat-injection-state-machines
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/teams/agent_state_machine_test.exs test/loomkin/teams/agent_broadcast_test.exs --max-failures 3` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/agent_state_machine_test.exs test/loomkin/teams/agent_broadcast_test.exs --max-failures 3`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | INTV-04a | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 0 | INTV-04b | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 0 | INTV-04c | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 0 | INTV-04f | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-05 | 01 | 0 | INTV-01a | unit | `mix test test/loomkin/teams/agent_broadcast_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-06 | 01 | 0 | INTV-01b | integration | `mix test test/loomkin_web/live/workspace_broadcast_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-07 | 01 | 0 | INTV-04d | integration | `mix test test/loomkin_web/live/workspace_state_machine_test.exs` | ❌ W0 | ⬜ pending |
| 05-01-08 | 01 | 0 | INTV-04e | unit | `mix test test/loomkin_web/live/agent_card_component_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/teams/agent_state_machine_test.exs` — stubs for INTV-04a, INTV-04b, INTV-04c, INTV-04f
- [ ] `test/loomkin/teams/agent_broadcast_test.exs` — stubs for INTV-01a
- [ ] `test/loomkin_web/live/workspace_broadcast_test.exs` — stubs for INTV-01b
- [ ] `test/loomkin_web/live/workspace_state_machine_test.exs` — stubs for INTV-04d
- [ ] `test/loomkin_web/live/agent_card_component_test.exs` — stubs for INTV-04e

*Existing infrastructure covers framework setup — only test files needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Composer broadcast mode indicator visually distinct | INTV-01c | Visual UI check | Toggle composer between agent and broadcast modes, verify icon/label changes |
| Resume vs permission controls visually distinct | INTV-04e | Visual UI check | With an agent in paused state and another in permission-pending, verify different button styles |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
