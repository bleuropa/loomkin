# Phase 7: Confidence Triggers - Research

**Researched:** 2026-03-08
**Domain:** Elixir/Phoenix LiveView — Agent GenServer rate limiting, multi-question batching, AskUser UI expansion
**Confidence:** HIGH

## Summary

Phase 7 is a pure extension of the already-working AskUser pipeline. The tool, signal, registry pattern, WorkspaceLive handler, and AgentCardComponent expansion slot all exist. The planner does not need to design new infrastructure — it needs to wire rate limiting into `build_loop_opts/1`'s `on_tool_execute` callback (where AskUser is already intercepted), add two new GenServer state fields, adapt the existing AskUserComponent to a multi-question batched list with a "Let the team decide" button, update the agent card overlay to use cyan instead of violet, and handle the collective-decide fallback via a `Process.send_after` timeout in the tool task (mirroring the approval gate timeout pattern exactly).

The key insight is that AskUser blocking already happens inside the tool task process (not the GenServer), and the `on_tool_execute` callback in `build_loop_opts/1` is where AskUser is already given special treatment (bypassing Jido.Exec's 60s limit). Rate limiting and batching intercept at exactly this same callback — before the tool task calls `AskUser.run/2`.

**Primary recommendation:** Intercept AskUser in `on_tool_execute` in `build_loop_opts/1`, check rate limit via a `GenServer.call` to the agent process, and either allow/batch the question or return a canned drop result immediately. The tool itself (`ask_user.ex`) stays unchanged.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Confidence detection mechanism:**
- The agent explicitly calls AskUser when uncertain — same tool, no new params or flags
- AgentLoop does NOT detect uncertainty from LLM output; the tool call IS the confidence signal
- All team AskUser calls are rate-limited (approval gates use RequestApproval, so they're naturally excluded from the rate limit — no special logic needed)
- Rate limiter state lives in the Teams.Agent GenServer — a `last_asked_at` timestamp field
- Rate limit check happens before the tool task process blocks (intercept at the GenServer level)

**Rate limiting and batching:**
- Batching IS the rate limit — one pending AskUser card per agent at a time
- If the agent asks again while a card is already open, the new question appends to the existing open card (sequential list: Q1, Q2, Q3 — each with its own answer slot)
- Questions added to an already-open card do not create a second card
- Calls that arrive when the card is open AND within the cooldown window are silently dropped — agent receives a canned tool result: "Rate limit reached — proceeding autonomously"
- 5-minute cooldown starts from when the last question in the batch was answered (not from when the card opened)
- After the cooldown expires, the agent can create a new card with a fresh question

**"Let the team decide" fallback:**
- Every AskUser card has a "Let the team decide" button alongside the human answer options
- Clicking it triggers CollectiveDecision among the other agents in the team — asking agent's tool call returns with the peer consensus answer
- Timeout (5 minutes, same as AskUser tool's existing default) also routes to CollectiveDecision — same fallback path as explicit dismissal
- The asking agent receives the collective answer and continues — no separate "dismissed" flag needed

### Claude's Discretion

- Exact canned text for rate-limited drops ("proceeding autonomously" is the intent; exact wording flexible)
- CollectiveDecision invocation details (timeout for peer vote, quorum rules)
- Whether a comms feed event is emitted when a question is rate-limited and dropped
- Whether the batched card shows a count badge ("3 pending questions") in the card header

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTV-03 | Agents auto-ask human when uncertain via confidence-threshold triggers from AgentLoop | Rate limit via `last_asked_at` field in Agent GenServer state; intercept in `on_tool_execute`; batching appends to open card; collective-decide fallback on dismiss or timeout; card anchored to agent in AgentCardComponent with cyan accent |
</phase_requirements>

---

## Standard Stack

### Core (all already in the codebase — no new dependencies)

| Component | Location | Purpose |
|-----------|----------|---------|
| `Loomkin.Tools.AskUser` | `lib/loomkin/tools/ask_user.ex` | Unchanged — blocks tool task process, registers via Registry, emits `AskUserQuestion` signal |
| `Loomkin.Teams.Agent` | `lib/loomkin/teams/agent.ex` | GenServer — gains `last_asked_at` and `pending_ask_user` fields; rate-limit guard in `on_tool_execute` callback |
| `Loomkin.Signals.Team.AskUserQuestion` | `lib/loomkin/signals/team.ex` | Existing signal, already classified critical in TeamBroadcaster |
| `LoomkinWeb.AskUserComponent` | `lib/loomkin_web/live/ask_user_component.ex` | Expand to multi-question list with "Let the team decide" button (currently single-question, violet — change to cyan) |
| `LoomkinWeb.AgentCardComponent` | `lib/loomkin_web/live/agent_card_component.ex` | Already has `pending_question` overlay — needs to show sequential question list, status dot changed from violet to cyan |
| `LoomkinWeb.WorkspaceLive` | `lib/loomkin_web/live/workspace_live.ex` | New `handle_event("let_team_decide", ...)` event; existing `{:ask_user_question, ...}` handler already sets card `pending_question` |
| `Loomkin.Teams.TeamBroadcaster` | `lib/loomkin/teams/team_broadcaster.ex` | `team.ask_user.question` already in `@critical_types` — no changes needed |

### No New Dependencies

No additional hex packages required. All OTP primitives needed (`Process.send_after`, `Registry`, `GenServer.call`) are already in use in this codebase.

---

## Architecture Patterns

### Existing AskUser Flow (baseline — Phase 7 builds on this)

```
Agent Loop Task
  └─ on_tool_execute callback
       └─ AskUser.run/2 called directly (bypassing Jido.Exec 60s limit)
            ├─ Registry.register {:ask_user, question_id}
            ├─ Signals.publish AskUserQuestion (critical → instant delivery)
            └─ receive {:ask_user_answer, ...} | after 300_000 (5 min)

WorkspaceLive
  ├─ handle_info {:ask_user_question, ...} → pending_questions list + agent card update
  └─ handle_event "ask_user_answer" → send {:ask_user_answer, question_id, answer} to registry pid
```

### Pattern 1: Rate Limit Guard in on_tool_execute (LOCKED DECISION)

The `build_loop_opts/1` private function in `agent.ex` constructs the `on_tool_execute` closure at loop-start time. This closure already specially handles `AskUser` (calls `tool_module.run/2` directly). The rate limit check inserts before that call.

**Key constraint:** The closure captures `state` at loop-start, so rate limit state changes after the loop starts are invisible to the closure. The rate limit check must call back to the GenServer to read current state.

```elixir
# In build_loop_opts/1, inside on_tool_execute:
on_tool_execute: fn tool_module, tool_args, context ->
  if tool_module == Loomkin.Tools.AskUser do
    agent_pid = self()  # captured at build time — this IS the agent GenServer pid
    case GenServer.call(agent_pid, {:check_ask_user_rate_limit, tool_args}) do
      :allow ->
        atomized = Loomkin.Tools.Registry.atomize_keys(tool_args)
        result = try do
          tool_module.run(atomized, context)
        rescue
          e -> {:error, Exception.message(e)}
        end
        AgentLoop.format_tool_result(result)

      {:batch, card_id} ->
        # Append question to existing open card
        GenServer.call(agent_pid, {:append_ask_user_question, tool_args, card_id})
        # Then block this tool task process waiting for answer (same as AskUser.run/2)
        question_id = tool_args["question_id"]  # set by GenServer before returning
        receive do
          {:ask_user_answer, ^question_id, answer} ->
            AgentLoop.format_tool_result({:ok, %{result: "User answered: #{answer}", answer: answer}})
        after
          300_000 ->
            # Trigger collective-decide fallback
            # ...
        end

      :drop ->
        AgentLoop.format_tool_result({:ok, %{result: "Rate limit reached — proceeding autonomously", answer: nil}})
    end
  else
    AgentLoop.default_run_tool(tool_module, tool_args, context)
  end
end
```

**Caution:** The `build_loop_opts/1` closure captures `self()` at build time (the agent GenServer pid). In the current codebase, this is already used for the checkpoint callback. The rate limit check can use the same `agent_pid` capture.

### Pattern 2: Agent GenServer State Extension

The `defstruct` in `agent.ex` gains two fields:

```elixir
defstruct [
  # ... existing fields ...
  last_asked_at: nil,          # monotonic timestamp of last answered question
  pending_ask_user: nil        # %{card_id, questions: [...], started_at}
]
```

The `handle_cast(:request_pause, %{status: :approval_pending})` clause (line 678) shows the pattern for adding a new status guard. A similar guard is needed for `:ask_user_pending`.

### Pattern 3: AskUser Card Timeout via Process.send_after (mirrors approval gate)

The `RequestApproval` tool uses `after timeout_ms ->` in the `receive` block to handle timeout. The AskUser tool already does this too (300_000ms). The Phase 7 change: when the timeout fires OR when "Let the team decide" is clicked, the answer value sent back to the blocking tool task process is `"Collective: #{winner}"` (same format as the existing `handle_collective_decision/2` helper in workspace_live.ex already produces).

### Pattern 4: WorkspaceLive "let_team_decide" Event

The existing `handle_event("ask_user_answer", ...)` at line 695 already handles `answer == "__collective__"` by calling `handle_collective_decision/2`. Phase 7 needs a dedicated "let_team_decide" event (or can reuse the `__collective__` answer sentinel already in place — see Anti-Patterns below).

The existing `handle_collective_decision/2` (lines 4332–4380) broadcasts a `PeerMessage` signal, collects votes in a background Task.Supervisor task (30s), and calls `send_ask_user_answer/2` with `"Collective: #{winner}"`. This mechanism is fully reusable.

### Pattern 5: AskUserComponent Multi-Question Display

Current `AskUserComponent` renders `@questions` as a loop — each question gets its own card. For batching, the component needs to show all questions for a given agent in one card, in order, with individual answer buttons per question. The `pending_questions` list in WorkspaceLive socket assigns already groups by question_id, but the component currently renders each question independently.

For the batched model: `pending_questions` will hold a list of questions all belonging to one open batch card. The component renders them as a sequential list within one card container.

### Anti-Patterns to Avoid

- **Changing AskUser tool signature:** Locked decision — `ask_user.ex` is unchanged. Rate limiting and batching happen in the GenServer, not the tool.
- **Using a new signal type for rate-limited drops:** The rate-limited drop returns directly to the tool task (`GenServer.call` returns `:drop`) — no signal is emitted (unless Claude's discretion decides otherwise).
- **Detecting confidence from LLM output/streaming tokens:** Locked out. The tool call IS the confidence signal.
- **Reusing `__collective__` button directly for "Let the team decide":** The current component labels this "Let the collective decide" with amber styling. Phase 7 calls it "Let the team decide" with the same mechanism but the CONTEXT.md specifies it as a distinct button on the card alongside per-question answer buttons. Can use the same `__collective__` sentinel value but render with cyan styling.
- **Blocking the Agent GenServer in the rate-limit check:** The rate-limit `GenServer.call` from within the `on_tool_execute` closure runs in the **tool task process** (Task.Supervisor child), not the Agent GenServer itself. `GenServer.call` from the tool task to the agent GenServer is the correct pattern — same as how the checkpoint callback works.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Peer vote collection for collective fallback | Custom vote aggregator | Existing `handle_collective_decision/2` in workspace_live.ex (lines 4332–4380) |
| Registry-based answer routing | Custom pid registry | `Registry` module with `{:ask_user, question_id}` key — already in use |
| Signal delivery to LiveView | Direct PubSub | TeamBroadcaster (already classifies `team.ask_user.question` as critical) |
| Countdown timer on card | Custom JS | `CountdownTimer` JS hook already used for approval gates |

---

## Common Pitfalls

### Pitfall 1: Closure Captures Stale State

**What goes wrong:** `build_loop_opts/1` builds a closure that captures `state` at loop-start. If `last_asked_at` or `pending_ask_user` are read directly from the closure-captured `state`, they will always reflect the state at loop-start — not current state.

**Why it happens:** Elixir closures capture values, not references. The loop runs in a separate Task.Supervisor child process with no access to the GenServer's live state.

**How to avoid:** The `on_tool_execute` closure must `GenServer.call(agent_pid, {:check_ask_user_rate_limit, ...})` to read current rate limit state. The agent GenServer processes this call with current state and returns `:allow | {:batch, card_id} | :drop`. The closure does not read `state` fields directly for rate limiting.

**Warning signs:** Rate limit never triggers even after many AskUser calls during one loop.

### Pitfall 2: Batch Card Answer Routing

**What goes wrong:** When multiple questions are batched into one card, each question has its own `question_id` registered in the AgentRegistry. When the human clicks an answer for Q2, the handler must route to Q2's registry pid — not Q1's. If the batched display shows questions in a loop without distinct `phx-value-question-id`, all buttons route to the same question.

**How to avoid:** Each question in the batch keeps its own `question_id` and registers independently in the Registry. The AskUserComponent renders each question with its own answer buttons scoped by `question_id`. The `handle_event("ask_user_answer", ...)` handler already uses `question_id` for routing — the batched model just shows multiple of these in one card.

**Warning signs:** Answering Q2 in a batch doesn't unblock Q2's waiting tool task.

### Pitfall 3: Cooldown Window Semantics

**What goes wrong:** Starting the 5-minute cooldown from when the card opens (rather than from when the last question is answered) creates an edge case where a card with many questions could have its cooldown expire while questions are still pending.

**How to avoid:** Per locked decision: the 5-minute cooldown starts from when the **last question in the batch is answered**. The agent state field `last_asked_at` is updated only when an answer is received (in `handle_call(:ask_user_answer, ...)` in the GenServer), not when the question is submitted.

### Pitfall 4: "Let the team decide" on a Batched Card

**What goes wrong:** If the human clicks "Let the team decide" on a batched card with 3 pending questions, does it resolve all 3 or just Q1?

**How to avoid:** Per the success criteria: "the agent proceeds autonomously using collective-decide fallback." This means all pending questions in the batch are resolved via collective decide simultaneously when "Let the team decide" is clicked. The handler should call `handle_collective_decision/2` for each pending question in the batch, then clear the batch. Alternatively, resolve the first pending question and let subsequent ones block until answered individually — but the simpler model is to resolve all pending when the button is clicked.

**Recommendation:** Resolve all pending questions in the batch when "Let the team decide" is clicked (one collective decision per question in sequence, or the same winner applied to all).

### Pitfall 5: Status State Machine

**What goes wrong:** The agent status needs an `ask_user_pending` state for the cyan pulsing dot and "Waiting for you" label. The existing `set_status_and_broadcast/2` guards against duplicate transitions. If `ask_user_pending` is not a recognized status atom in `status_dot_class/1` and `status_label/1` in AgentCardComponent, the dot will not render correctly.

**How to avoid:** Add `:ask_user_pending` to the card component's status dot/label functions. Follow the same pattern as `:approval_pending` (violet dot) — but with `bg-cyan-500 animate-pulse` for cyan.

---

## Code Examples

### Existing Rate-Limit Architecture in Agent GenServer (baseline)

```elixir
# lib/loomkin/teams/agent.ex — existing RateLimiter (for LLM provider calls)
rate_limiter: fn provider ->
  RateLimiter.acquire(provider, 1000)
end,
```

Note: this existing `RateLimiter` is for LLM API rate limiting — **not** the AskUser rate limit. The AskUser rate limit is a new, separate mechanism using `last_asked_at` timestamp comparison in the agent GenServer state.

### Existing on_tool_execute AskUser Intercept (extends this)

```elixir
# lib/loomkin/teams/agent.ex — build_loop_opts/1
on_tool_execute: fn tool_module, tool_args, context ->
  context =
    if tool_module == Loomkin.Tools.ContextOffload do
      Map.put(context, :agent_messages, state.messages)
    else
      context
    end

  # AskUser blocks waiting for human input (up to 5 min), so bypass the
  # default 60s Jido.Exec timeout and call run/2 directly.
  if tool_module == Loomkin.Tools.AskUser do
    atomized = Loomkin.Tools.Registry.atomize_keys(tool_args)
    result =
      try do
        tool_module.run(atomized, context)
      rescue
        e -> {:error, Exception.message(e)}
      end
    AgentLoop.format_tool_result(result)
  else
    AgentLoop.default_run_tool(tool_module, tool_args, context)
  end
end
```

Phase 7 adds a rate-limit check before `tool_module.run/2` is called here.

### Existing Collective Decision Invocation (WorkspaceLive)

```elixir
# lib/loomkin_web/live/workspace_live.ex — lines 4332–4380
defp handle_collective_decision(socket, question) do
  # Sends PeerMessage signal, collects votes in Task.Supervisor background task,
  # calls send_ask_user_answer/2 with "Collective: #{winner}"
  # ...
end
```

This is the reusable fallback path for "Let the team decide". Phase 7 wires the "Let the team decide" button click to call this same helper.

### Existing Approval Gate Status Pattern in AgentCardComponent

```elixir
# lib/loomkin_web/live/agent_card_component.ex — approval panel (lines 402–447)
<div
  :if={@card.status == :approval_pending && @card[:pending_approval]}
  class="border-t border-violet-500/30 bg-violet-950/20 px-4 py-3 flex flex-col gap-2"
>
  ...
</div>
```

Phase 7 adds an analogous `ask_user_pending` panel below card content, with `border-cyan-500/30 bg-cyan-950/20` styling.

### Existing AskUser Card Overlay (in AgentCardComponent)

```elixir
# lib/loomkin_web/live/agent_card_component.ex — lines 121–173
<div
  :if={@card.pending_question}
  class="absolute inset-0 z-10 rounded-lg p-4 flex flex-col overflow-auto"
  ...
>
  <p ...>{@card.pending_question.question}</p>
  <div class="flex flex-wrap gap-1.5 mt-auto">
    <button :for={option <- @card.pending_question.options} phx-click="ask_user_answer" ...>
      {option}
    </button>
    <button phx-value-answer="__collective__" ...>Collective</button>
  </div>
</div>
```

Phase 7 replaces this overlay with an expanded panel below card content (same as approval gate) showing a sequential list of questions, each with its own answer buttons, and one "Let the team decide" button at the bottom of the panel.

---

## State of the Art

| Old Approach | Current Approach | Impact for Phase 7 |
|--------------|-----------------|-------------------|
| AskUser overlay on agent card (absolute positioned) | Approval gate uses appended panel below card content | Phase 7 should use the approval gate panel pattern (appended below), not the existing absolute overlay — per CONTEXT.md "identical pattern to approval gates" |
| Single question per AskUser card | Multi-question batch in one card | The `pending_question` agent card field (map) needs to become a list, or the batch is managed at WorkspaceLive level via `pending_questions` list filtered by agent |
| `__collective__` sentinel answered via existing button | Dedicated "Let the team decide" button with same mechanics | New button label, same Registry + vote mechanism |

---

## Open Questions

1. **Batch card ownership in socket assigns**
   - What we know: `pending_questions` in WorkspaceLive socket is a flat list of all agent questions. The agent card gets `pending_question: %{...}` (singular map). For batching, the agent card needs to show a list.
   - What's unclear: Does the agent card field become `pending_questions: [...]` (plural, list), or does the batching happen only in AskUserComponent (which already iterates `@questions`)? The CONTEXT.md says "appends to the existing open card" — suggesting the agent card itself shows the list.
   - Recommendation: Change agent card field from `pending_question` (singular map) to `pending_questions` (list of question maps). WorkspaceLive `handle_info({:ask_user_question, ...})` appends to the existing list for that agent's card when a batch is open.

2. **"Let the team decide" on multi-question batch resolution scope**
   - What we know: CONTEXT.md says clicking "Let the team decide" triggers CollectiveDecision — the asking agent's tool call returns with peer consensus.
   - What's unclear: When multiple questions are batched, does one click resolve all pending questions, or just the first?
   - Recommendation (Claude's discretion): Apply collective decide to all pending questions in the batch at once, using the same winner for each, to unblock all waiting tool task processes simultaneously.

3. **Rate-limit drop comms feed event**
   - What we know: CONTEXT.md marks this as Claude's discretion.
   - Recommendation: Emit a comms feed event when a question is rate-limited and dropped. Use the existing `append_activity_event` pattern with `:system` agent and a short informational message. This gives the human visibility into why an agent went silent.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built into Elixir) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin/teams/agent_ask_user_rate_limit_test.exs --no-start` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTV-03 | Rate limit blocks second AskUser within cooldown window | unit | `mix test test/loomkin/teams/agent_ask_user_rate_limit_test.exs -x` | ❌ Wave 0 |
| INTV-03 | Second AskUser while card open appends to existing card | unit | `mix test test/loomkin/teams/agent_ask_user_rate_limit_test.exs -x` | ❌ Wave 0 |
| INTV-03 | "Let the team decide" click resolves blocking tool task with collective answer | unit | `mix test test/loomkin_web/live/workspace_live_ask_user_test.exs -x` | ❌ Wave 0 |
| INTV-03 | AskUser card renders with cyan accent in agent card component | unit | `mix test test/loomkin_web/live/workspace_live_ask_user_test.exs -x` | ❌ Wave 0 |
| INTV-03 | AskUser timeout routes to collective-decide fallback | unit | `mix test test/loomkin/tools/ask_user_test.exs -x` | ❌ Wave 0 |
| INTV-03 | Rate-limited drop returns canned result immediately | unit | `mix test test/loomkin/teams/agent_ask_user_rate_limit_test.exs -x` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `mix test test/loomkin/teams/agent_ask_user_rate_limit_test.exs test/loomkin_web/live/workspace_live_ask_user_test.exs --no-start`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/loomkin/teams/agent_ask_user_rate_limit_test.exs` — covers rate limit guard, batch append, drop behavior (REQ INTV-03)
- [ ] `test/loomkin_web/live/workspace_live_ask_user_test.exs` — covers "let_team_decide" event, card update, collective fallback wiring (REQ INTV-03)
- [ ] `test/loomkin/tools/ask_user_test.exs` — covers existing AskUser tool + timeout-to-collective path (REQ INTV-03)

Note: `test/loomkin/tools/request_approval_test.exs` is the closest existing model for tool test structure. `test/loomkin_web/live/workspace_live_approval_test.exs` is the closest model for WorkspaceLive handler tests.

---

## Sources

### Primary (HIGH confidence)

All findings are based on direct codebase inspection — no external sources required. The implementation decisions are locked in CONTEXT.md and the codebase patterns are directly readable.

- `lib/loomkin/tools/ask_user.ex` — current AskUser tool: blocks, registers, receives, unregisters
- `lib/loomkin/tools/request_approval.ex` — approval gate pattern: exact model for timeout-then-fallback
- `lib/loomkin/tools/collective_decision.ex` — collective vote tool: quorum, vote collection, 30s internal timeout
- `lib/loomkin/teams/agent.ex` (full file) — GenServer state, `build_loop_opts/1`, `on_tool_execute` intercept, `set_status_and_broadcast/2`
- `lib/loomkin_web/live/agent_card_component.ex` — approval panel pattern (lines 402–447), existing pending_question overlay (lines 121–173), status dot classes
- `lib/loomkin_web/live/workspace_live.ex` — `handle_event("ask_user_answer", ...)`, `handle_info({:ask_user_question, ...})`, `handle_collective_decision/2`, `pending_questions` socket assign
- `lib/loomkin_web/live/ask_user_component.ex` — current single-question rendering with `__collective__` sentinel
- `lib/loomkin/teams/team_broadcaster.ex` — `@critical_types` MapSet confirms `team.ask_user.question` is already critical
- `lib/loomkin/signals/team.ex` — `AskUserQuestion` and `AskUserAnswered` signal definitions and schema

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components directly inspected in codebase
- Architecture patterns: HIGH — all patterns traced from existing working implementations (AskUser tool, approval gate, collective decision helper, TeamBroadcaster)
- Pitfalls: HIGH — identified from direct code analysis (closure capture, registry routing, cooldown semantics)
- Validation: HIGH — test file structure directly modeled on existing `request_approval_test.exs` and `workspace_live_approval_test.exs`

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable codebase; valid until significant refactor)
