---
phase: 6
slug: approval-gates
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built into Elixir/OTP) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/tools/request_approval_test.exs test/loomkin_web/live/agent_card_component_test.exs --no-start` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/tools/request_approval_test.exs test/loomkin_web/live/agent_card_component_test.exs --no-start`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 6-01-01 | 01 | 0 | INTV-02 | unit | `mix test test/loomkin/tools/request_approval_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 6-01-02 | 01 | 0 | INTV-02 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 6-01-03 | 01 | 0 | INTV-02 | unit | `mix test test/loomkin_web/live/agent_card_component_test.exs --no-start` | ✅ needs update | ⬜ pending |
| 6-01-04 | 01 | 0 | INTV-02 | integration | `mix test test/loomkin_web/live/workspace_live_approval_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 6-02-01 | 02 | 1 | INTV-02 | unit | `mix test test/loomkin/tools/request_approval_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 6-02-02 | 02 | 1 | INTV-02 | unit | `mix test test/loomkin_web/live/agent_card_component_test.exs --no-start` | ✅ needs update | ⬜ pending |
| 6-03-01 | 03 | 2 | INTV-02 | integration | `mix test test/loomkin_web/live/workspace_live_approval_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 6-03-02 | 03 | 2 | INTV-02 | integration | `mix test test/loomkin_web/live/workspace_live_approval_test.exs --no-start` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/tools/request_approval_test.exs` — stubs for blocking approval, response routing, and timeout behavior (INTV-02)
- [ ] `test/loomkin/teams/team_broadcaster_test.exs` — verify critical_types includes approval signal types (file may or may not exist)
- [ ] `test/loomkin_web/live/workspace_live_approval_test.exs` — integration tests for LiveView event handlers and leader banner (INTV-02)
- [ ] Update `test/loomkin_web/live/agent_card_component_test.exs` — update `:approval_pending` dot assertion (amber → violet) and add approval panel render tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Approval card is visually distinct from permission hook card | INTV-02 | Visual design comparison requires human judgment | Open workspace, trigger RequestApproval and a permission hook side by side; verify different card design, labels, positioning |
| Countdown timer ticks down in JS hook | INTV-02 | JS hook behavior requires browser interaction | Trigger approval gate with short timeout; observe timer counts down to 0 without server round-trips |
| Team-wide banner appears when leader agent hits approval gate | INTV-02 | Multi-agent banner visibility requires live browser check | Start multi-agent workspace with leader; trigger leader RequestApproval; verify banner appears for all team members |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
