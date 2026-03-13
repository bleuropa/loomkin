---
phase: 10-leader-research-protocol
plan: "01"
subsystem: api
tags: [elixir, roles, system-prompt, research-protocol, llm-instructions]

# Dependency graph
requires:
  - phase: 10-leader-research-protocol
    provides: wave 0 stub tests for research protocol content
provides:
  - lead system_prompt with ## Research Protocol section encoding the 6-step first-message protocol
  - researcher system_prompt with ## Findings Delivery section and structured peer_message format
  - green role_test assertions confirming protocol content is present
affects: [10-leader-research-protocol, agent-boot, team-sessions]

# Tech tracking
tech-stack:
  added: []
  patterns: [system-prompt-as-config, tdd-red-green for prompt content, base-prompt-extension before context-awareness injection]

key-files:
  created: []
  modified:
    - lib/loomkin/teams/role.ex
    - test/loomkin/teams/role_test.exs

key-decisions:
  - "Research Protocol appended to base lead system_prompt (before append_context_awareness injection), not as a separate module attribute — keeps the protocol co-located with the role definition it governs"
  - "Findings Delivery section in researcher prompt uses markdown headings ## Research Findings and ## Recommendation matching the exact format the lead synthesizes — ensures consistent structure across the protocol"

patterns-established:
  - "Protocol-as-config: LLM behavior for multi-step workflows is encoded exclusively in system_prompt sections, not in GenServer logic"
  - "TDD for prompt content: write failing assertions on string contains before extending the prompt string"

requirements-completed: [LEAD-02]

# Metrics
duration: 12min
completed: 2026-03-08
---

# Phase 10 Plan 01: Research Protocol System Prompts Summary

**Lead and researcher system prompts extended with research protocol instructions: 6-step first-message protocol in lead, structured findings delivery format in researcher, verified via green role_test assertions**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-08T23:00:00Z
- **Completed:** 2026-03-08T23:12:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Extended lead `system_prompt` with `## Research Protocol (First Message Only)` section containing all 6 steps (team_spawn with spawn_type: "research", wait for peer_message findings, synthesize, ask_user, team_dissolve)
- Extended researcher `system_prompt` with `## Findings Delivery` section specifying peer_message delivery format with `## Research Findings` and `## Recommendation` headings
- Unskipped and implemented both Wave 0 stub tests in role_test.exs; all 32 role tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend role.ex with research protocol prompts** - `d8da348` (feat)

**Plan metadata:** _(docs commit pending)_

_Note: TDD task — RED phase (unskip + real assertions) run first, GREEN phase (prompt extension) second, both in single atomic commit._

## Files Created/Modified
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/role.ex` - Added ## Research Protocol to lead system_prompt and ## Findings Delivery to researcher system_prompt
- `/Users/vinnymac/Sites/vinnymac/loomkin/test/loomkin/teams/role_test.exs` - Replaced @tag :skip + flunk stubs with real assertions against Role.get/1 return values

## Decisions Made
- Research Protocol appended directly to base lead system_prompt before the closing `"""` — co-located with the role definition, not in a separate module attribute
- Findings Delivery in researcher prompt uses exact markdown headings matching what lead will synthesize, ensuring consistent structured format across the protocol
- Fixed pre-existing `telegex` dependency compile error (run `mix deps.compile telegex --force`) that blocked the lefthook pre-commit format check — this is a pre-existing environment issue, not introduced by this plan

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Pre-existing `telegex` dependency compilation failure blocked lefthook pre-commit hook on first commit attempt. Resolved by running `mix deps.compile telegex --force`. This is a pre-existing environment issue unrelated to this plan's changes.

## Next Phase Readiness
- Research protocol is now encoded as LLM configuration in role.ex
- Wave 1 plan 02 can proceed to implement team_spawn with spawn_type: "research" support in the TeamSpawn tool
- All role tests green; no regressions introduced

---
*Phase: 10-leader-research-protocol*
*Completed: 2026-03-08*

## Self-Check: PASSED
- FOUND: lib/loomkin/teams/role.ex
- FOUND: test/loomkin/teams/role_test.exs
- FOUND: .planning/phases/10-leader-research-protocol/10-01-SUMMARY.md
- FOUND: commit d8da348
