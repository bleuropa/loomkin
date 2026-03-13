---
phase: 10
slug: leader-research-protocol
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built into Elixir/OTP) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin/teams/agent_research_protocol_test.exs test/loomkin/teams/role_test.exs --no-start` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/agent_research_protocol_test.exs test/loomkin/teams/role_test.exs --no-start`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-W0-01 | Wave 0 | 0 | LEAD-01 | unit stub | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 10-W0-02 | Wave 0 | 0 | LEAD-02 | unit stub | `mix test test/loomkin/teams/role_test.exs --no-start` | ✅ (extend) | ⬜ pending |
| 10-01-01 | 01 | 1 | LEAD-02 | unit | `mix test test/loomkin/teams/role_test.exs --no-start` | ✅ (extend) | ⬜ pending |
| 10-02-01 | 02 | 1 | LEAD-01 | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 10-02-02 | 02 | 1 | LEAD-01 | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 10-02-03 | 02 | 1 | LEAD-01 | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ W0 | ⬜ pending |
| 10-03-01 | 03 | 2 | LEAD-01 | manual | N/A — visual UI state | ✅ human verify | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/teams/agent_research_protocol_test.exs` — stubs for LEAD-01: spawn_type intercept, budget check, `:awaiting_synthesis` transition
- [ ] Extend `test/loomkin/teams/role_test.exs` — add stub assertions for research protocol section in lead prompt and findings format in researcher prompt

*Existing `test/loomkin/teams/role_test.exs` covers the role file — only extensions needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Leader card shows indigo pulsing "Awaiting synthesis" dot while researchers work | LEAD-01, LEAD-02 | LiveView visual state — hard to automate dot color/animation in ExUnit | Start a team session, observe leader card status updates as research sub-agents run |
| AskUser question card includes "Here's what I found:" synthesis from researcher findings | LEAD-01 | End-to-end LLM behavior — prompt quality can't be unit tested | Trigger a research session, verify the human's question includes a research summary |
| Research sub-agents visible in team tree with active status | LEAD-01 | Tree rendering requires full LiveView session | Confirm team tree shows researcher nodes while leader awaits synthesis |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
