---
phase: 8
slug: dynamic-tree-visibility
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | test/test_helper.exs |
| **Quick run command** | `mix test test/loomkin/teams/nested_teams_test.exs test/loomkin/teams/team_broadcaster_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/loomkin/teams/nested_teams_test.exs test/loomkin/teams/team_broadcaster_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 0 | TREE-02 | unit | `mix test test/loomkin/tools/team_spawn_test.exs` | ❌ W0 | ⬜ pending |
| 8-01-02 | 01 | 0 | TREE-02 | unit | `mix test test/loomkin/teams/agent_child_teams_test.exs` | ❌ W0 | ⬜ pending |
| 8-01-03 | 01 | 0 | TREE-01 | integration | `mix test test/loomkin_web/live/workspace_live_tree_test.exs` | ❌ W0 | ⬜ pending |
| 8-01-04 | 01 | 0 | TREE-01 | unit | `mix test test/loomkin_web/live/team_tree_component_test.exs` | ❌ W0 | ⬜ pending |
| 8-02-01 | 02 | 1 | TREE-02 | unit | `mix test test/loomkin/teams/nested_teams_test.exs` | ✅ | ⬜ pending |
| 8-02-02 | 02 | 1 | TREE-02 | unit | `mix test test/loomkin/tools/team_spawn_test.exs` | ❌ W0 | ⬜ pending |
| 8-02-03 | 02 | 1 | TREE-01 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs` | ✅ | ⬜ pending |
| 8-03-01 | 03 | 2 | TREE-02 | unit | `mix test test/loomkin/teams/agent_child_teams_test.exs` | ❌ W0 | ⬜ pending |
| 8-04-01 | 04 | 3 | TREE-01 | integration | `mix test test/loomkin_web/live/workspace_live_tree_test.exs` | ❌ W0 | ⬜ pending |
| 8-05-01 | 05 | 4 | TREE-01 | unit | `mix test test/loomkin_web/live/team_tree_component_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/loomkin/tools/team_spawn_test.exs` — stubs for TREE-02 (signal NOT published from tool after migration)
- [ ] `test/loomkin/teams/agent_child_teams_test.exs` — stubs for TREE-02 (terminate/2 calls Manager.dissolve_team for each child)
- [ ] `test/loomkin_web/live/workspace_live_tree_test.exs` — stubs for TREE-01 (team_tree assign updated on signal, dissolution walk)
- [ ] `test/loomkin_web/live/team_tree_component_test.exs` — stubs for TREE-01 (component renders, open/close, node selection)

*Existing infrastructure (nested_teams_test.exs, team_broadcaster_test.exs) covers existing patterns; Wave 0 adds new test files for new behaviors.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| TeamTreeComponent visually shows indented tree in toolbar | TREE-01 | Visual rendering and popover UX requires browser verification | Spawn a sub-team, verify tree trigger appears in toolbar; click it, verify indented node list shows team name and agent count |
| Tree node disappears when sub-team dissolves | TREE-01 | LiveView DOM mutation requires browser verification | Dissolve a child team, verify its node is removed from the tree dropdown without page reload |
| Leader agent OTP restart terminates child teams (no zombies) | TREE-02 | Requires process crash simulation in running system | Kill a leader agent process (via Observer or :erlang.exit), verify child teams are dissolved and not visible in tree |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
