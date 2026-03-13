---
phase: 7
slug: confidence-triggers
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/teams/ test/loomkin_web/live/workspace_live_confidence_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/ test/loomkin_web/live/workspace_live_confidence_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 0 | INTV-03 | unit stub | `mix test test/loomkin/teams/agent_confidence_test.exs` | ❌ W0 | ⬜ pending |
| 7-01-02 | 01 | 1 | INTV-03 | unit | `mix test test/loomkin/teams/agent_confidence_test.exs` | ❌ W0 | ⬜ pending |
| 7-02-01 | 02 | 0 | INTV-03 | unit stub | `mix test test/loomkin_web/live/workspace_live_confidence_test.exs` | ❌ W0 | ⬜ pending |
| 7-02-02 | 02 | 1 | INTV-03 | integration | `mix test test/loomkin_web/live/workspace_live_confidence_test.exs` | ❌ W0 | ⬜ pending |
| 7-03-01 | 03 | 1 | INTV-03 | unit | `mix test test/loomkin/teams/agent_confidence_test.exs` | ❌ W0 | ⬜ pending |
| 7-03-02 | 03 | 2 | INTV-03 | integration | `mix test test/loomkin_web/live/workspace_live_confidence_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/teams/agent_confidence_test.exs` — stubs for rate limit guard and batch routing in Teams.Agent
- [ ] `test/loomkin_web/live/workspace_live_confidence_test.exs` — stubs for AskUser card expansion, batching UI, and "Let the team decide" button

*Existing `test/loomkin/tools/ask_user_test.exs` (if any) and `test/loomkin_web/live/workspace_live_approval_test.exs` provide fixture patterns.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cyan pulsing dot visible on agent card while AskUser pending | INTV-03 | CSS animation not testable in ExUnit | Load workspace with a mock AskUser-pending agent; verify `bg-cyan-500 animate-pulse` dot renders |
| "Let the team decide" triggers CollectiveDecision and resolves card | INTV-03 | Requires live agent processes + vote collection | Start team session, have agent call AskUser, click "Let the team decide," verify card closes and agent receives collective answer |
| Rate limit: second AskUser call within 5 min is silently dropped | INTV-03 | Requires live agent runtime + timing | Have agent call AskUser twice in <5 min; verify only one card appears and agent receives canned drop message |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
