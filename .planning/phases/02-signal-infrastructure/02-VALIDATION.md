---
phase: 02
slug: signal-infrastructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/teams/topics_test.exs test/loomkin/teams/team_broadcaster_test.exs --trace` |
| **Full suite command** | `mix test --trace` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (Topics + TeamBroadcaster tests)
- **After every plan wave:** Run `mix test --trace`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | FOUN-03 | unit | `mix test test/loomkin/teams/topics_test.exs --trace` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 1 | FOUN-02 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs --trace` | ❌ W0 | ⬜ pending |
| 02-03-01 | 03 | 2 | FOUN-02,FOUN-03 | integration | `mix test test/loomkin_web/live/workspace_live_test.exs --trace` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/teams/topics_test.exs` — stubs for Topics module
- [ ] `test/loomkin/teams/team_broadcaster_test.exs` — stubs for TeamBroadcaster

*Existing infrastructure covers framework and fixtures.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Message queue under 50 with 10 agents | FOUN-02 SC5 | Requires running agents | Start 10-agent team, observe `:erlang.process_info(pid, :message_queue_len)` during sustained streaming |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
