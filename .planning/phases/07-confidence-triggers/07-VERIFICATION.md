---
phase: 07-confidence-triggers
verified: 2026-03-08T20:45:00Z
status: human_needed
score: 5/5 must-haves verified
human_verification:
  - test: "Visual confirmation of cyan pulsing status dot when agent has a pending AskUser question"
    expected: "Agent card shows bg-cyan-500 animate-pulse dot and 'Waiting for you' label"
    why_human: "CSS animation (animate-pulse) and live dot color cannot be verified by grep alone; requires live browser rendering"
  - test: "Batched panel renders below card content (not as overlay) when agent sends two AskUser calls while card is open"
    expected: "Second question appends inside the same cyan panel; no second card or overlay appears"
    why_human: "Real-time LiveView patch behavior and DOM layout require browser interaction to confirm"
  - test: "Clicking 'Let the team decide' closes the panel and the agent resumes"
    expected: "Panel disappears and the agent's status dot returns to its working/idle color"
    why_human: "End-to-end LiveView event routing (GenServer -> Registry -> blocked receive) cannot be exercised without a running application"
  - test: "Rate-limit drop: a second AskUser call within 5 minutes of an answered card creates NO new card"
    expected: "No new cyan panel appears; agent continues silently"
    why_human: "Requires timing across two tool invocations with a live agent loop; not exercisable in unit tests"
---

# Phase 7: Confidence Triggers Verification Report

**Phase Goal:** Agents automatically surface a question to the human when their confidence drops below a threshold, with rate limiting to prevent interrupt fatigue
**Verified:** 2026-03-08T20:45:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| #  | Truth | Status | Evidence |
|----|-------|--------|---------|
| 1  | When an agent calls AskUser, the question surfaces to the human in the existing AskUser UI | VERIFIED | `on_tool_execute` in `agent.ex` intercepts `AskUser` calls, rate-limit `:allow` path executes `AskUser.run/2` unchanged; `handle_info({:ask_user_question, ...})` in `workspace_live.ex` dispatches to both `AskUserComponent` (legacy) and the new agent card panel |
| 2  | Multiple low-confidence questions from the same agent are batched into a single review card | VERIFIED | `pending_questions` list (not singular map) on agent card assigns; `handle_info({:ask_user_question, ...})` appends to `existing_card_questions` list; `AgentCardComponent` renders all questions with `:for={q <- @card[:pending_questions] \|\| []}` |
| 3  | An agent cannot trigger more than one confidence-threshold question card per five minutes | VERIFIED | `handle_call({:check_ask_user_rate_limit, ...})` in `agent.ex` uses `cond` with monotonic-time 300,000 ms window; returns `:drop` when `last_asked_at` within window and `pending_ask_user == nil`; `last_asked_at` set only on `{:ask_user_answered, ...}` so cooldown starts from answer, not submission |
| 4  | Human can dismiss with "Let the team decide" and agent proceeds via collective-decide fallback | VERIFIED | `handle_event("let_team_decide", ...)` in `workspace_live.ex` calls `handle_collective_decision/2` for every question belonging to the named agent via `Enum.reduce`; agent receives collective answer; card cleared |
| 5  | Confidence trigger pathway wired from AgentLoop through signal bus to AskUserComponent | VERIFIED | `on_tool_execute` closure captures `agent_pid = self()` (GenServer pid at build time); `GenServer.call(agent_pid, {:check_ask_user_rate_limit, tool_args})` dispatches before `AskUser.run/2`; `handle_cast({:append_ask_user_question, ...})` publishes `AskUserQuestion` signal to signal bus; `workspace_live.ex` receives via `handle_info(%Jido.Signal{type: "team.ask_user.question"} = sig, socket)` |

**Score: 5/5 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/loomkin/teams/agent_confidence_test.exs` | 9 passing tests covering rate-limit guard, batch append, drop, cooldown | VERIFIED | 9 tests, 0 skipped, 0 failures confirmed by `mix test` |
| `test/loomkin_web/live/workspace_live_ask_user_test.exs` | 9 passing tests covering batching, let_team_decide, card component helpers | VERIFIED | 9 tests, 0 skipped, 0 failures confirmed by `mix test` |
| `lib/loomkin/teams/agent.ex` | `last_asked_at`, `pending_ask_user` fields; rate-limit handle_call; on_tool_execute intercept; ask_user_pending pause guard | VERIFIED | All 5 must-haves confirmed by grep: defstruct fields at lines 50-51, handle_call at line 669, on_tool_execute intercept at line 2072, handle_cast pause guard at line 732 |
| `lib/loomkin_web/live/workspace_live.ex` | `let_team_decide` event handler, batched `pending_questions` in handle_info, card init with `pending_questions: []` | VERIFIED | `handle_event("let_team_decide", ...)` at line 717; `handle_info({:ask_user_question, ...})` appends to list at line 2204; agent card init map has `pending_questions: []` at line 4016 |
| `lib/loomkin_web/live/agent_card_component.ex` | Cyan AskUser panel, `:ask_user_pending` status dot/label/card_state_class, no absolute overlay | VERIFIED | Panel at line 442 with `border-cyan-500/30 bg-cyan-950/20`; `status_dot_class(:ask_user_pending)` → `"bg-cyan-500 animate-pulse"` at line 520; `status_label(:ask_user_pending)` → `"Waiting for you"` at line 534; `card_state_class(..., :ask_user_pending)` → `"agent-card-asking"` at line 490; no `absolute inset-0 z-10` overlay block found for pending_question |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `on_tool_execute` closure in `build_loop_opts/1` | `GenServer.call(agent_pid, {:check_ask_user_rate_limit, tool_args})` | `agent_pid = self()` captured at build time | WIRED | Confirmed at `agent.ex` line 2070-2072 |
| `handle_call({:check_ask_user_rate_limit, ...})` | `state.pending_ask_user` and `state.last_asked_at` | `cond` pattern matching on live GenServer state | WIRED | Lines 669-683 in `agent.ex` |
| Agent card panel `phx-click="let_team_decide"` | `workspace_live.handle_event("let_team_decide", %{"agent" => agent_name}, socket)` | `phx-value-agent={@card.name}` attribute | WIRED | Panel button at `agent_card_component.ex` line 471; handler at `workspace_live.ex` line 717 |
| `workspace_live.handle_event("let_team_decide")` | `handle_collective_decision/2` | `Enum.reduce` over pending questions for that agent | WIRED | Lines 722-725 in `workspace_live.ex` |
| `workspace_live.handle_info({:ask_user_question, question})` | `update_agent_card(socket, agent_name, %{pending_questions: updated_card_questions})` | Appends to `existing_card_questions` list | WIRED | Lines 2218-2235 in `workspace_live.ex` |

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| INTV-03 | 07-01, 07-02, 07-03, 07-04 | Agents auto-ask human when uncertain via confidence-threshold triggers from AgentLoop | SATISFIED | Rate-limit guard in `agent.ex`, cyan card UI in `agent_card_component.ex`, batched `pending_questions` in `workspace_live.ex`, `let_team_decide` event handler — all verified above. REQUIREMENTS.md shows INTV-03 marked `[x]` as Complete for Phase 7. |

No orphaned requirements — only INTV-03 is mapped to Phase 7 in REQUIREMENTS.md and all four plans claim it.

---

### Anti-Patterns Found

Scanning key files modified in this phase:

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/loomkin/teams/agent.ex` | 2088-2090 | `if question_id do` — `ask_user_answered` skipped when no `question_id` in `tool_args` on the `:allow` path | Info | Legacy AskUser calls without a question_id will not set `last_asked_at` after answering; the cooldown window will not activate. This is a known deviation documented in 07-02-SUMMARY.md and intentional for backward compatibility. |

No blockers found. No FIXME/TODO/placeholder comments in modified files. No empty implementations.

---

### Human Verification Required

The automated checks (18/18 tests passing, all key links wired) confirm the backend logic and component structure are correct. The following behaviors require live browser verification because they depend on CSS animation rendering and real-time LiveView socket patches:

#### 1. Cyan pulsing status dot

**Test:** Start the dev server at http://loom.test:4200. Open a team workspace with an active agent and trigger an AskUser call (via test fixture or actual agent uncertainty). Observe the agent card.
**Expected:** Status dot becomes cyan (`bg-cyan-500`) and pulses (Tailwind `animate-pulse`). Status label reads "Waiting for you".
**Why human:** CSS animation class presence is confirmed by grep, but whether the animation visually renders and is noticeable requires live browser rendering.

#### 2. Batched panel renders below card content (not as overlay)

**Test:** With a card open for an agent, trigger a second AskUser call from the same agent before answering the first.
**Expected:** The second question appears appended inside the same cyan panel below the card content area. No second card opens; no absolute overlay appears.
**Why human:** LiveView DOM patching and panel layout position (below content vs. overlay) must be verified visually in a live browser.

#### 3. "Let the team decide" resolves all batched questions

**Test:** Open a card with two pending questions. Click "Let the team decide".
**Expected:** The cyan panel closes. Both questions are resolved via collective-decide fallback. Agent status returns to its working/idle color.
**Why human:** End-to-end flow (GenServer state cleared, Registry entries released, agent blocked processes unblocked) requires a running application with connected agent processes to verify.

#### 4. Rate-limit drop — no second card within cooldown

**Test:** Answer an AskUser card. Within 5 minutes, trigger another AskUser call from the same agent.
**Expected:** No new cyan panel appears. The agent continues silently (drop path returns canned text to the agent's tool task).
**Why human:** Timing-sensitive behavior across two tool invocations with a live agent loop; not exercisable without running agent workers.

---

## Gaps Summary

None. All automated verification passed. Phase 7 is pending final human confirmation of visual and real-time behaviors (Tasks 2 of 07-04 Plan), which the 07-04-SUMMARY.md reports as already completed by the human on 2026-03-08. If that human sign-off is accepted as sufficient, this phase is fully complete.

---

_Verified: 2026-03-08T20:45:00Z_
_Verifier: Claude (gsd-verifier)_
