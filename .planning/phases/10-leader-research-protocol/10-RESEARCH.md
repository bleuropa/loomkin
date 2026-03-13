# Phase 10: Leader Research Protocol - Research

**Researched:** 2026-03-08
**Domain:** Elixir/Phoenix LiveView — GenServer state extension, system prompt engineering, spawn gate intercept, LiveComponent status UI
**Confidence:** HIGH

## Summary

Phase 10 layers a structured multi-step research protocol on top of the existing agent/spawn/signal infrastructure built in Phases 5–9. Every team session starts with the leader spawning research sub-agents, waiting for their peer_message findings, synthesizing them, and then calling AskUser — all before any implementation work begins. The protocol replaces uninformed first-questions with informed briefings.

The implementation surface is deliberately narrow: three system prompt additions (lead role, researcher role, and structured findings format), one new status atom (`:awaiting_synthesis`), one new auto-approve path keyed on `spawn_type: :research`, and one new UI card state in `AgentCardComponent`. All underlying mechanics — peer_message delivery, spawn gate intercept, budget check, AskUser tool, TeamDissolve — already exist and are used unchanged.

The key architectural question is where the leader transitions to `:awaiting_synthesis`. The cleanest pattern, consistent with how `:approval_pending` is set via `open_spawn_gate` cast, is a new `handle_cast({:enter_awaiting_synthesis, ...})` that the tool task process sends immediately after the research spawn is approved and before blocking on researcher peer_messages.

**Primary recommendation:** Follow the Phase 9 spawn gate pattern exactly — add the `spawn_type: :research` check at the top of `run_spawn_gate_intercept/5`, set `:awaiting_synthesis` status via GenServer cast from the tool task, accumulate peer_messages in the tool task receive loop (not the GenServer), and transition back to `:working` once all researchers have reported.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Research protocol fires on the **first message** of a team session — not on every subsequent message
- Always runs — no complexity threshold, no opt-in keyword required; every team session starts with research
- Leader autonomously decides how many researchers to spawn based on how many distinct research questions exist (1–3 typical, bounded by budget)
- Leader card shows a new **"Awaiting Synthesis"** status while researchers work — distinct from :active
- New status atom (`:awaiting_synthesis`) with indigo/blue pulsing dot, consistent with the amber/purple/cyan pattern from Phases 6–7
- Researcher sub-agents appear in the team tree with `:active` (working) status — no new status atom needed for researchers
- Researchers deliver findings to the leader via **peer_message** — reuses the existing peer communication tool
- Leader waits for **all spawned researchers** to report before synthesizing (not incremental)
- Researcher system prompt defines a **structured findings format** (## Research Findings / ## Recommendation)
- Leader composes a question that naturally opens with "Here's what I found: ..." before the actual question
- Research cost visible via **existing budget bar on researcher agent cards** in the tree panel — no new UI element needed
- Leader **dissolves the research sub-team** after receiving the human's answer, calling `team_dissolve`
- Research spawns are **auto-approved** — skip the Phase 9 spawn gate UI
- Leader passes **`spawn_type: :research`** in `team_spawn` tool args to signal auto-approval
- `agent.ex` intercept checks for `spawn_type: :research` and bypasses the gate
- **Budget check still runs** — auto-approval skips the human gate but not the safety floor
- Research orchestration prompts defined in `lib/loomkin/teams/role.ex` in the lead role's `system_prompt`
- Multi-step protocol encoded as prompt instructions (not runtime-configurable) — code-level only

### Claude's Discretion

- Exact indigo/blue shade for "Awaiting Synthesis" dot (should complement existing amber/purple/cyan palette)
- Exact system prompt wording for the research protocol steps
- Whether a comms feed event fires when the leader enters "awaiting synthesis" state
- Whether the AskUser question includes the word count or agent count of the research phase

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LEAD-01 | Leader agent spawns research sub-agents, synthesizes findings, then poses informed questions to human | spawn_type: :research auto-approve path + `:awaiting_synthesis` status + peer_message accumulation in tool task receive loop |
| LEAD-02 | Leader role config with research orchestration prompts and multi-step protocol | `lib/loomkin/teams/role.ex` lead + researcher system_prompt sections |
</phase_requirements>

---

## Standard Stack

### Core — All existing, no new dependencies

| Module | Location | Purpose |
|--------|----------|---------|
| `Loomkin.Teams.Agent` | `lib/loomkin/teams/agent.ex` | GenServer to extend: new status atom, new spawn-type check, new cast handler |
| `Loomkin.Teams.Role` | `lib/loomkin/teams/role.ex` | System prompt home: lead prompt extension + researcher findings format |
| `LoomkinWeb.AgentCardComponent` | `lib/loomkin_web/live/agent_card_component.ex` | UI: add `:awaiting_synthesis` to `status_dot_class/1`, `status_label/1`, `card_state_class/2` |
| `Loomkin.Tools.TeamSpawn` | `lib/loomkin/tools/team_spawn.ex` | No changes — leader calls this with `spawn_type: :research` param |
| `Loomkin.Tools.PeerMessage` | `lib/loomkin/tools/peer_message.ex` | No changes — researchers call this to deliver findings |
| `Loomkin.Tools.TeamDissolve` | `lib/loomkin/tools/team_dissolve.ex` | No changes — leader calls this after human answers |
| `Loomkin.Tools.AskUser` | `lib/loomkin/tools/ask_user.ex` | No changes — leader calls this after synthesis |

**Installation:** No new packages needed.

---

## Architecture Patterns

### Established Pattern: Tool Task Intercept (Phase 9)

The Phase 9 spawn gate intercept runs entirely in the tool task process (the closure passed as `on_tool_execute`), never in the GenServer. The GenServer only receives a lightweight cast to update its status for broadcast. This is the exact pattern Phase 10 extends.

Current intercept shape (simplified):

```elixir
# Source: lib/loomkin/teams/agent.ex ~line 2150
on_tool_execute: fn tool_module, tool_args, context ->
  agent_pid = self()
  # ...
  if tool_module == Loomkin.Tools.TeamSpawn do
    run_spawn_gate_intercept(agent_pid, tool_module, tool_args, context, team_id, name)
  else
    AgentLoop.default_run_tool(tool_module, tool_args, context)
  end
end
```

The `run_spawn_gate_intercept/5` function checks `auto_approve_spawns` and either calls `run_human_spawn_gate/9` or `execute_spawn_and_notify/7`.

### Pattern 1: Research Auto-Approve Path

Phase 10 adds a pre-check at the **top** of `run_spawn_gate_intercept/5` before the existing double-gate check:

```elixir
defp run_spawn_gate_intercept(agent_pid, tool_module, tool_args, context, team_id, agent_name) do
  spawn_type = Map.get(tool_args, "spawn_type", Map.get(tool_args, :spawn_type))

  if spawn_type == :research or spawn_type == "research" do
    run_research_spawn(agent_pid, tool_module, tool_args, context, team_id, agent_name)
  else
    # existing Phase 9 gate logic unchanged
    roles = Map.get(tool_args, "roles", Map.get(tool_args, :roles, []))
    ...
  end
end
```

The `run_research_spawn/6` function:
1. Runs the budget check (same as Phase 9)
2. If budget ok: calls `execute_spawn_and_notify/7` directly (nil gate_id, same as auto_approve path)
3. Casts `:enter_awaiting_synthesis` to the agent GenServer
4. Blocks on a receive loop accumulating peer_message findings from all spawned researchers
5. When all findings received: transitions agent back to `:working` via cast, returns the synthesized findings as the tool result

### Pattern 2: Awaiting Synthesis Status Atom

Add to the existing status pattern in `agent.ex`:

```elixir
# In handle_cast clauses for request_pause (mirrors :approval_pending and :ask_user_pending):
def handle_cast(:request_pause, %{status: :awaiting_synthesis} = state) do
  broadcast_team(state, {:agent_pause_queued, state.name})
  {:noreply, %{state | pause_queued: true}}
end

# New cast to enter the state:
def handle_cast({:enter_awaiting_synthesis, researcher_count}, state) do
  state = set_status_and_broadcast(state, :awaiting_synthesis)
  {:noreply, state}
end

# New cast to exit the state:
def handle_cast(:exit_awaiting_synthesis, state) do
  state = set_status_and_broadcast(state, :working)
  {:noreply, state}
end
```

### Pattern 3: Peer Message Accumulation in Tool Task

The tool task process receives peer_messages through `handle_info/2` in the GenServer, which appends them to `state.messages`. However, for the research protocol we need the **tool task** to capture findings directly — not the GenServer — because the tool task is blocking in a receive loop and needs to return a synthesized result back to AgentLoop.

The approach: the tool task accumulates findings in its own local variable via `receive` with a count-down:

```elixir
defp collect_research_findings(researcher_count, timeout_ms, acc) when researcher_count > 0 do
  receive do
    {:research_findings, from, content} ->
      collect_research_findings(researcher_count - 1, timeout_ms, [{from, content} | acc])
  after
    timeout_ms -> acc  # partial findings on timeout
  end
end
defp collect_research_findings(0, _timeout, acc), do: acc
```

This requires researchers to send `{:research_findings, name, content}` to the leader's tool task pid — but the existing `peer_message` tool sends through Comms/PubSub to the GenServer, not to the tool task. **Resolution:** The leader's GenServer `handle_cast({:peer_message, from, content})` needs to forward findings to the waiting tool task pid if `:awaiting_synthesis` status is active.

The tool task registers itself before blocking so the GenServer can route to it:

```elixir
# In run_research_spawn, before blocking:
Registry.register(Loomkin.Teams.AgentRegistry, {:awaiting_synthesis, team_id, agent_name}, self())

# In handle_cast({:peer_message, from, content}, %{status: :awaiting_synthesis} = state):
case Registry.lookup(AgentRegistry, {:awaiting_synthesis, team_id, name}) do
  [{tool_task_pid, _}] ->
    send(tool_task_pid, {:research_findings, from, content})
  [] -> nil  # fallback: append to messages normally
end
{:noreply, state}
```

This mirrors exactly the `Registry.register(AgentRegistry, {:spawn_gate, gate_id}, self())` pattern in Phase 9.

### Pattern 4: Role Config Extension (LEAD-02)

Lead system prompt gains a new section appended after the existing content:

```
## Research Protocol (First Message Only)
When you receive the first message in a team session, before doing anything else:
1. Identify 1–3 distinct research questions needed to answer the task well
2. Call team_spawn with spawn_type: "research" to create a research sub-team
3. Wait — you will receive findings from each researcher via peer_message
4. When all researchers have reported, synthesize their findings
5. Call ask_user with a question that opens "Here's what I found:" followed by the synthesis and your specific question
6. After the human answers, call team_dissolve on the research team, then proceed with implementation

On subsequent messages in the same session, skip this protocol and answer directly.
```

Researcher system prompt gains a structured findings section:

```
## Findings Format
Always deliver your final findings using peer_message to the team lead in this exact format:

## Research Findings
[Key observations with file_path:line_number references, patterns found, confirmed facts vs inferences]

## Recommendation
[Suggested approach or ranked options with brief rationale]

Send this as soon as your research is complete — do not wait to be asked.
```

### Anti-Patterns to Avoid

- **Sending findings back to GenServer messages then parsing them:** The tool task needs to receive findings as a direct signal, not parse them out of the agent's accumulated `state.messages`. Use the Registry routing approach.
- **Status transition in the tool task without a cast:** `set_status_and_broadcast/2` is a private GenServer function. The tool task must cast to the GenServer to trigger status changes.
- **Blocking the GenServer during synthesis:** The tool task runs in a separate process. The GenServer must remain responsive to status broadcasts and peer_message routing during the `receive` block.
- **Skipping budget check for research spawns:** The decisions are explicit: auto-approve skips the human gate, not the budget check. Budget check must run first.
- **Adding `spawn_type` to the TeamSpawn tool schema as required:** It should be optional — existing spawns omit it and hit the Phase 9 human gate path as before.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Findings delivery | Custom findings signal/bus | Existing `peer_message` tool + GenServer routing | peer_message already handles cross-team delivery via Comms.send_to/3 |
| Auto-approve routing | New gate bypass field on Agent struct | Check `spawn_type` in `run_spawn_gate_intercept/5` | Phase 9 gate already has auto_approve path; just add a new pre-check |
| Status broadcast | Custom broadcast in tool task | `GenServer.cast(agent_pid, :enter_awaiting_synthesis)` | `set_status_and_broadcast/2` lives in GenServer; only GenServer can call it |
| Tool task coordination | GenServer state tracking | `Registry` for tool task pid routing | Phase 9 uses same pattern for `{:spawn_gate, gate_id}` |
| Research team cleanup | Background monitor/supervisor | `team_dissolve` tool called by leader via prompt instruction | TeamDissolve already exists and works |

---

## Common Pitfalls

### Pitfall 1: Determining "first message" in the leader's ReAct loop

**What goes wrong:** The leader's system prompt says "first message only" but the LLM doesn't track this reliably across tool calls within the same session turn. It may attempt research again mid-session.

**Why it happens:** The LLM's only ground truth is its conversation history and system prompt instructions.

**How to avoid:** The system prompt instruction "on subsequent messages in the same session, skip this protocol" is the primary control. Optionally, the leader's state can track `research_done: boolean` and inject a context message if the protocol fires again. The simplest approach (matching the locked decision) is prompt-only — rely on the conversation history showing the prior research exchange as evidence.

**Warning signs:** If integration testing shows the leader re-spawning researchers on second messages, add a GenServer flag `research_phase_complete: boolean` and inject a system message at the start of subsequent turns.

### Pitfall 2: Race between research spawn result and `:awaiting_synthesis` cast

**What goes wrong:** The tool task calls `execute_spawn_and_notify`, gets back a result, then sends the cast — but a researcher finishes and sends peer_message before the Registry registration happens.

**Why it happens:** Same race that Phase 9 solved for spawn gate registration.

**How to avoid:** Register the tool task with `Registry.register(AgentRegistry, {:awaiting_synthesis, team_id, agent_name}, self())` **before** calling `execute_spawn_and_notify`. The cast for status update can come after. Peer_messages that arrive before the tool task registers will be handled by the GenServer's default `handle_cast({:peer_message, ...})` clause and added to messages normally — a safe fallback.

### Pitfall 3: `spawn_type` key format mismatch (atom vs string)

**What goes wrong:** The LLM generates `spawn_type` as a string `"research"` but the check compares against atom `:research`.

**Why it happens:** Tool args from LLM JSON arrive as string-keyed maps. Phase 9 already handles this pattern for `roles` with `Map.get(tool_args, "roles", Map.get(tool_args, :roles, []))`.

**How to avoid:** Check both atom and string forms:
```elixir
spawn_type = Map.get(tool_args, "spawn_type", Map.get(tool_args, :spawn_type))
if spawn_type in [:research, "research"] do
```

### Pitfall 4: TeamSpawn schema rejects unknown `spawn_type` param

**What goes wrong:** `Jido.Action` schema validation rejects `spawn_type` as an unknown parameter before the tool runs.

**Why it happens:** TeamSpawn schema currently has only `team_name`, `roles`, `project_path`.

**How to avoid:** Add `spawn_type: [type: :atom, required: false, doc: "..."]` to TeamSpawn schema. The intercept reads it from `tool_args` in `on_tool_execute` before the tool runs, so the tool itself doesn't need to handle it, but schema validation must allow it.

### Pitfall 5: Leader's AskUser blocks while research team still alive

**What goes wrong:** Leader calls `ask_user` before calling `team_dissolve`, so research agents keep running and accumulating cost during the human's response window.

**Why it happens:** The prompt instructs the leader to dissolve **after** the human answers — not before asking.

**How to avoid:** This is correct per the locked decisions. Research team is alive during the AskUser window (cost is visible in the tree). Budget bar shows accumulated cost. Leader dissolves after receiving the answer. No fix needed — but verify in integration testing that the tree shows research agents as `:idle` (complete) not `:active` during the AskUser window, to avoid misleading the human.

---

## Code Examples

### Status dot pattern (existing, for reference)

```elixir
# Source: lib/loomkin_web/live/agent_card_component.ex ~line 689
defp status_dot_class(:working), do: "bg-green-400 agent-dot-working"
defp status_dot_class(:approval_pending), do: "bg-violet-500 animate-pulse"
defp status_dot_class(:ask_user_pending), do: "bg-cyan-500 animate-pulse"
# Phase 10 adds:
defp status_dot_class(:awaiting_synthesis), do: "bg-indigo-500 animate-pulse"
```

### Status label pattern (existing, for reference)

```elixir
# Source: lib/loomkin_web/live/agent_card_component.ex ~line 706
defp status_label(:approval_pending), do: "Awaiting approval"
defp status_label(:ask_user_pending), do: "Waiting for you"
# Phase 10 adds:
defp status_label(:awaiting_synthesis), do: "Awaiting synthesis"
```

### Card state class pattern (existing, for reference)

```elixir
# Source: lib/loomkin_web/live/agent_card_component.ex ~line 662
defp card_state_class(_content_type, :approval_pending), do: "agent-card-approval"
defp card_state_class(_content_type, :ask_user_pending), do: "agent-card-asking"
# Phase 10 adds:
defp card_state_class(_content_type, :awaiting_synthesis), do: "agent-card-awaiting-synthesis"
```

### pause guard pattern (existing, must extend)

```elixir
# Source: lib/loomkin/teams/agent.ex ~line 779
def handle_cast(:request_pause, %{status: :approval_pending} = state) do
  broadcast_team(state, {:agent_pause_queued, state.name})
  {:noreply, %{state | pause_queued: true}}
end
# Phase 10 adds same clause for :awaiting_synthesis
```

### Existing auto-approve path (Phase 9, for reference — research mirrors this)

```elixir
# Source: lib/loomkin/teams/agent.ex ~line 2263
if auto_approve do
  # Step 6 directly: execute spawn with nil gate_id (no GateResolved published)
  execute_spawn_and_notify(agent_pid, tool_module, tool_args, context, nil, team_id, agent_name)
else
  run_human_spawn_gate(...)
end
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Leader asks human immediately on first message | Leader runs research protocol first | Phase 10 target |
| All spawns go through human gate (Phase 9) | Research spawns auto-approved via `spawn_type: :research` | Phase 10 addition |
| No `:awaiting_synthesis` status | New status atom with indigo dot | Phase 10 addition |
| Researcher prompt has no findings format | Structured `## Research Findings / ## Recommendation` format | Phase 10 addition |

---

## Open Questions

1. **Does the leader need a GenServer flag to suppress repeat research?**
   - What we know: Prompt-only control is the locked approach
   - What's unclear: Whether a single LLM session reliably respects the "first message only" instruction across many conversation turns
   - Recommendation: Start with prompt-only; add `research_phase_complete: boolean` to Agent struct only if integration testing shows re-triggering

2. **What if fewer researchers report than were spawned (e.g., one crashes)?**
   - What we know: Leader waits for all spawned researchers per locked decisions
   - What's unclear: Timeout behavior — partial findings vs. full stall
   - Recommendation: Add a per-researcher timeout in the receive loop (e.g., 120s per researcher); on timeout, accumulate what arrived and proceed with synthesis noting partial findings

3. **Comms feed event on `:awaiting_synthesis` transition?**
   - What we know: Left to Claude's discretion in CONTEXT.md
   - Recommendation: Yes — a status change event in the comms feed (same as other state transitions) helps the human understand why the leader is quiet. Low implementation cost; use existing `set_status_and_broadcast/2` which already publishes an Agent.Status signal.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built into Elixir/OTP) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LEAD-01 | `spawn_type: :research` triggers auto-approve path in `run_spawn_gate_intercept/5` | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ Wave 0 |
| LEAD-01 | Budget check still runs for research spawns | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ Wave 0 |
| LEAD-01 | Agent transitions to `:awaiting_synthesis` after research spawn | unit | `mix test test/loomkin/teams/agent_research_protocol_test.exs --no-start` | ❌ Wave 0 |
| LEAD-02 | Lead role system prompt contains research protocol section | unit | `mix test test/loomkin/teams/role_test.exs --no-start` | ✅ (extend) |
| LEAD-02 | Researcher role system prompt contains structured findings format | unit | `mix test test/loomkin/teams/role_test.exs --no-start` | ✅ (extend) |

### Sampling Rate

- **Per task commit:** `mix test test/loomkin/teams/agent_research_protocol_test.exs test/loomkin/teams/role_test.exs --no-start`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/loomkin/teams/agent_research_protocol_test.exs` — covers LEAD-01 spawn_type intercept, budget check, `:awaiting_synthesis` status transition
- [ ] Extend `test/loomkin/teams/role_test.exs` — add assertions for research protocol section in lead prompt and findings format in researcher prompt

---

## Sources

### Primary (HIGH confidence)
- Direct source read: `lib/loomkin/teams/agent.ex` — spawn gate intercept pattern (~line 2150–2450), `set_status_and_broadcast/2` (~line 2872), peer_message handling (~line 856, 1311), status atom clauses
- Direct source read: `lib/loomkin_web/live/agent_card_component.ex` — `status_dot_class/1`, `status_label/1`, `card_state_class/2` patterns
- Direct source read: `lib/loomkin/teams/role.ex` — lead role system prompt (lines 289–316), researcher role (lines 322–342)
- Direct source read: `lib/loomkin/tools/peer_message.ex` — delivery via Comms.send_to/3
- Direct source read: `lib/loomkin/tools/team_spawn.ex` — schema and run/2 shape
- Direct source read: `lib/loomkin/tools/team_dissolve.ex` — Manager.dissolve_team/1 call
- Direct source read: `.planning/phases/10-leader-research-protocol/10-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)
- Direct source read: `test/loomkin/teams/agent_spawn_gate_test.exs` — established test patterns for agent GenServer unit testing
- Direct source read: `test/loomkin/teams/agent_test.exs` — `start_agent` helper, `:sys.get_state` introspection pattern
- Direct source read: `test/loomkin/teams/role_test.exs` — role prompt assertion patterns

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all modules read directly from source
- Architecture patterns: HIGH — derived from Phase 9 spawn gate implementation (same file, same pattern)
- Pitfalls: HIGH — derived from Phase 9 race conditions and existing string/atom duality patterns
- System prompt wording: MEDIUM — content is at Claude's discretion per CONTEXT.md; structure is HIGH

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable codebase; no external dependencies)
