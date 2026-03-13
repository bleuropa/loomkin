# Phase 10: Leader Research Protocol - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

The leader agent follows a structured multi-step protocol on the first message of a new team session: spawn research sub-agents, wait for all findings, synthesize them, then pose an informed question to the human via AskUser. This replaces the current pattern of asking humans uninformed questions. The leader role config gains research orchestration prompts as code-level configuration. Subsequent messages within the same session are answered directly — research runs once per session start, not on every message.

</domain>

<decisions>
## Implementation Decisions

### Protocol trigger condition
- Research protocol fires on the **first message** of a team session — not on every subsequent message
- Always runs — no complexity threshold, no opt-in keyword required; every team session starts with research
- Leader autonomously decides how many researchers to spawn based on how many distinct research questions exist (1–3 typical, bounded by budget)

### Leader UI state during research
- Leader card shows a new **"Awaiting Synthesis"** status while researchers work — distinct from :active
- New status atom (e.g., `:awaiting_synthesis`) with indigo/blue pulsing dot, consistent with the amber/purple/cyan pattern from Phases 6–7
- Researcher sub-agents appear in the team tree with `:active` (working) status — no new status atom needed for researchers, tree visibility from Phase 8 covers this

### Researcher findings handoff
- Researchers deliver findings to the leader via **peer_message** — reuses the existing peer communication tool
- Leader waits for **all spawned researchers** to report before synthesizing (not incremental)
- Researcher system prompt defines a **structured findings format**:
  ```
  ## Research Findings
  [key observations, file references, patterns found]

  ## Recommendation
  [suggested approach or options]
  ```
- Leader system prompt instructs it to accumulate peer_message findings from all researchers, synthesize into one coherent summary, then call AskUser

### Informed question format
- **Same AskUser card** — no new card type; richness is in the question text, not the UI
- Leader composes a question that naturally opens with "Here's what I found: ..." before the actual question — the synthesis is part of the question text itself
- Research cost visible via **existing budget bar on researcher agent cards** in the tree panel — no new UI element needed; human can see cost before answering

### Research sub-team lifecycle
- Leader **dissolves the research sub-team** after receiving the human's answer
- Leader's system prompt instructs it to call `team_dissolve` on the research team before delegating implementation work to specialists
- Research team does not persist for follow-up — if more research is needed, leader spawns fresh

### Research spawn gate
- Research spawns are **auto-approved** — skip the Phase 9 spawn gate UI
- Leader passes **`spawn_type: :research`** in `team_spawn` tool args to signal auto-approval
- `agent.ex` intercept checks for `spawn_type: :research` and bypasses the gate
- **Budget check still runs** — auto-approval skips the human gate but not the safety floor. If research spawn exceeds remaining budget, blocked with same tool error as Phase 9.

### Leader role config (LEAD-02)
- Research orchestration prompts defined in `lib/loomkin/teams/role.ex` as a new section in the lead role's `system_prompt`
- Multi-step protocol encoded as prompt instructions (not runtime-configurable) — code-level only
- Researcher role's system prompt gains the structured findings format definition

### Claude's Discretion
- Exact indigo/blue shade for "Awaiting Synthesis" dot (should complement existing amber/purple/cyan palette)
- Exact system prompt wording for the research protocol steps
- Whether a comms feed event fires when the leader enters "awaiting synthesis" state
- Whether the AskUser question includes the word count or agent count of the research phase

</decisions>

<specifics>
## Specific Ideas

- The informed question should feel like a briefing before a decision — "Here's what I found, here's my recommendation, here's what I need from you" — not a dump of raw research output
- The structured findings format (## Research Findings / ## Recommendation) in the researcher prompt keeps synthesis deterministic without requiring JSON from LLMs

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/loomkin/teams/role.ex` — Lead role system prompt at lines 289–316. Phase 10 appends a research protocol section here. Researcher role at ~322–342 gains the structured findings format.
- `lib/loomkin/tools/ask_user.ex` — Existing AskUser tool; leader calls this unchanged after synthesis. No new tool needed.
- `lib/loomkin/tools/peer_message.ex` (PeerMessage) — Researchers call this to deliver findings. Existing tool, no changes.
- `lib/loomkin/tools/team_spawn.ex` — Leader calls this with `spawn_type: :research` flag. Intercept in agent.ex handles the flag.
- `lib/loomkin/tools/team_dissolve.ex` (TeamDissolve) — Leader calls this after human answers to clean up research sub-team.
- `AgentCardComponent` — Already has `:approval_pending`, `:ask_user_pending` states. Phase 10 adds `:awaiting_synthesis` state with indigo dot.
- Phase 9 spawn gate intercept in `agent.ex` `on_tool_execute` — Phase 10 extends this to check `spawn_type: :research` for auto-approve path.

### Established Patterns
- Status + dot color convention (Phase 6–7): amber=permission, purple=approval/spawn, cyan=confidence — indigo/blue for awaiting synthesis fits the pattern
- `set_status_and_broadcast/2` in Agent GenServer: `:awaiting_synthesis` status transition goes through here
- Spawn gate intercept in `agent.ex` `on_tool_execute` (Phase 9): research spawn adds a pre-check for `spawn_type == :research` before the full gate logic

### Integration Points
- `lib/loomkin/teams/role.ex`: Extend lead system prompt with research protocol. Extend researcher system prompt with structured findings format.
- `lib/loomkin/teams/agent.ex`: Add `:awaiting_synthesis` status atom. Add intercept in `on_tool_execute` for `spawn_type: :research` auto-approve path. Add `handle_info` for accumulating researcher peer_messages (or leader's ReAct loop handles this naturally via tool results).
- `lib/loomkin_web/live/agent_card_component.ex`: Add `:awaiting_synthesis` card state with indigo pulsing dot and "Awaiting synthesis" label.
- `lib/loomkin/signals/team.ex` or agent.ex: `:awaiting_synthesis` status emitted via Agent.Status signal so LiveView reflects it.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-leader-research-protocol*
*Context gathered: 2026-03-08*
