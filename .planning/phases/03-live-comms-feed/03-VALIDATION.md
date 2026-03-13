---
phase: 3
slug: live-comms-feed
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built into Elixir) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/loomkin_web/live/workspace_live_test.exs test/loomkin/teams/team_broadcaster_test.exs --trace` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin_web/live/workspace_live_test.exs test/loomkin/teams/team_broadcaster_test.exs --trace`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 0 | VISB-01 | unit | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs --trace` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 0 | VISB-01 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs --trace` | ✅ (needs new case) | ⬜ pending |
| 03-01-03 | 01 | 0 | VISB-02 | unit | `mix test test/loomkin_web/live/agent_comms_component_test.exs --trace` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 1 | VISB-01 | unit | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs --trace` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 1 | VISB-01 | integration | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs --trace` | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 1 | VISB-02 | unit | `mix test test/loomkin_web/live/workspace_live_test.exs --trace` | ✅ (needs expansion) | ⬜ pending |
| 03-04-01 | 04 | 2 | VISB-02 | unit | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs --trace` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin_web/live/workspace_live_peer_message_test.exs` — stubs for VISB-01a, VISB-01c, VISB-02b
- [ ] `test/loomkin_web/live/agent_comms_component_test.exs` — stubs for VISB-02c (component render test)
- [ ] New test case in `test/loomkin/teams/team_broadcaster_test.exs` — VISB-01b (critical classification)

*Existing infrastructure covers framework needs. No new dependencies required.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Auto-scroll follows new messages | VISB-02 | JS hook + DOM interaction requires browser | Open workspace, send 20+ messages, verify scroll stays at bottom |
| Card insertion glow animation | VISB-02 | CSS animation is visual-only | Spawn a new agent, observe 1.5s glow animation on new card |
| Agent color consistency across feed + card | VISB-01 | Visual verification across components | Compare agent card color with same agent's comms feed message color |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
