# Phase 9: Spawn Safety - Research

**Researched:** 2026-03-08
**Domain:** Elixir/Phoenix LiveView — GenServer intercept pattern, tool blocking, budget gating, session-scoped UI state
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Spawn Approval Card Design**
- Reuse Phase 6 purple/violet approval gate card design — same expand-in-place pattern, same accent color
- Spawn-specific card content replaces the generic "question" area:
  - Team name (from `team_spawn` params)
  - Planned agent composition: each role with count (e.g., "researcher x2, coder x1")
  - Estimated cost: "estimated ~$X" (approximate framing, not exact)
  - Warning line if planned spawn approaches max-agents-per-team or max-nesting-depth limits
- Action buttons: same three-button layout as Phase 6 — Approve / Deny / Approve w/ Context
  - Approve: one-click, no text required
  - Approve w/ Context: optional guidance text to the leader
  - Deny: optional denial reason text to the leader
- Leader receives structured denial: `{status: :denied, reason: :human_denied, message: human_text}` — same shape as Phase 6
- Timeout: 5-minute default, configurable per spawn via tool args. Auto-denies on timeout with structured reason `{status: :denied, reason: :timeout, ...}`. Same behavior as Phase 6.
- Auto-approve checkbox on the card: first spawn gate shows "Auto-approve future spawns" checkbox — toggling it enables auto-approve for the rest of the session

**Budget Threshold & Auto-Block**
- Remaining budget = `budget.limit - budget.spent` from `CostTracker.team_cost_summary` (same data the workspace UI already shows)
- If `remaining_budget < estimated_spawn_cost` → spawn is auto-blocked without surfacing an approval gate
- Leader receives a tool error result: `{:error, :budget_exceeded, %{remaining: X, estimated: Y}}`
- Leader handles the error in its own context (propose fewer agents, ask human to raise limit, etc.)
- No separate escalation banner for auto-block — tool error is sufficient
- Max-agents-per-team and max-nesting-depth limits: enforced server-side by `Manager` (depth=2 already enforced). When the planned spawn would bring counts to 80%+ of limits, a warning line appears in the spawn approval card. No separate persistent UI warning.

**Cost Estimation**
- Fixed per-agent estimates by role — hardcoded constants (e.g., researcher=$0.20, coder=$0.50, reviewer=$0.30, tester=$0.30, lead=$0.50)
- Estimate = sum of per-role estimates for all planned agents
- Displayed as "estimated ~$X" on the approval card
- Used for the budget threshold check (`remaining_budget < estimated_cost` → auto-block)

**Auto-Approve Mode**
- Toggle lives on the spawn approval card: "Auto-approve future spawns" checkbox visible on the first spawn gate
- Scope: session-scoped — resets on page reload, not persisted to DB
- In auto-approve mode: budget check still runs. If within budget → spawn proceeds immediately without showing a gate. If over budget → spawn is auto-blocked (same tool error path as above). Human gate is skipped, safety floor remains.

### Claude's Discretion
- Exact per-role cost estimate values (can be tuned based on typical agent usage)
- Whether to add a "bump limit" suggestion in the budget-exceeded tool error message to the leader
- Countdown timer visual on the spawn gate card (ring, bar, or text — consistent with Phase 6)
- Exact warning threshold for limit warnings (80% suggested above, but exact value is a tuning decision)
- Comms feed event for spawn gate open/resolved (whether to emit one and styling)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TREE-03 | Pre-spawn budget check and approval gate before spawning expensive sub-trees | Full pattern established: intercept in `on_tool_execute` for `team_spawn`, budget check via `CostTracker`, gate via Registry blocking + Jido signals, UI reuses Phase 6 approval card with spawn-specific fields |
</phase_requirements>

---

## Summary

Phase 9 adds a pre-spawn gating layer between the leader's call to `team_spawn` and the actual team creation in `Manager.create_sub_team/3`. The implementation follows the exact same blocking-tool intercept pattern established in Phase 6 for `RequestApproval` and in Phase 7 for `AskUser`. No new structural patterns are needed — the planner can reuse the existing blueprint almost verbatim.

The critical insight is that Phase 9 does **not** modify `Loomkin.Tools.TeamSpawn` itself. The intercept lives exclusively in `agent.ex`'s `on_tool_execute` closure, which already has a `team_spawn`-specific branch (currently only post-success tracking). This branch expands to add: budget check via `CostTracker.team_cost_summary`, estimated cost computation from locked-in per-role constants, optional approval gate (blocking `receive` on `{:spawn_gate_response, gate_id, decision}`), auto-approve mode (new field on agent state struct), and budget-exceeded early return. The agent GenServer keeps running; only the tool task process blocks.

The UI side mirrors Phase 6 exactly: new signal structs (`SpawnGateRequested`, `SpawnGateResolved`), new `handle_info` clauses in `workspace_live.ex`, new `handle_event` handlers for approve/deny/auto-approve-toggle, and extension of `AgentCardComponent`'s existing `:approval_pending` panel to distinguish spawn gates from checkpoint gates via a `type:` field in the `pending_approval` map.

**Primary recommendation:** Implement Phase 9 as a direct extension of the Phase 6 approval gate pattern. The existing infrastructure (Registry routing, `set_status_and_broadcast`, `@critical_types`, three-button card panel, countdown timer hook) is fully reusable with minimal adaptation.

---

## Standard Stack

### Core (all already in project)
| Module | Location | Purpose in Phase 9 |
|--------|----------|---------------------|
| `Loomkin.Teams.Agent` | `lib/loomkin/teams/agent.ex` | Add spawn gate intercept in `on_tool_execute`; add `auto_approve_spawns` to defstruct |
| `Loomkin.Teams.CostTracker` | `lib/loomkin/teams/cost_tracker.ex` | `team_cost_summary/1` returns `{total_cost_usd, ...}` for remaining budget check |
| `Loomkin.Teams.Manager` | `lib/loomkin/teams/manager.ex` | Already enforces `@default_max_nesting_depth 2`; query team agent count for 80% warning |
| `Loomkin.Teams.TeamBroadcaster` | `lib/loomkin/teams/team_broadcaster.ex` | Add spawn gate signal types to `@critical_types` MapSet |
| `LoomkinWeb.WorkspaceLive` | `lib/loomkin_web/live/workspace_live.ex` | New `handle_event` and `handle_info` clauses for spawn gate |
| `LoomkinWeb.AgentCardComponent` | `lib/loomkin_web/live/agent_card_component.ex` | Extend `:approval_pending` panel to support `type: :spawn_gate` variant |
| `Registry` (Erlang/OTP) | stdlib | Route `{:spawn_gate_response, gate_id, decision}` back to blocking tool task |
| `Loomkin.Signals` publish | `lib/loomkin/signals/` | Publish `SpawnGateRequested` and `SpawnGateResolved` Jido signals |

### New Files Required
| File | Purpose |
|------|---------|
| `lib/loomkin/signals/spawn.ex` | Define `SpawnGateRequested` and `SpawnGateResolved` signal structs |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New signal file `signals/spawn.ex` | Add to `signals/approval.ex` | Separate file is cleaner; spawn gate is conceptually different from checkpoint approval |
| Session-scoped auto-approve on agent state | LiveView socket assign only | Agent state is the single source of truth; socket-only would require a server round-trip to read |

---

## Architecture Patterns

### Pattern 1: `on_tool_execute` Intercept (established in Phase 6)

**What:** The `on_tool_execute` callback in `build_loop_opts/1` is a function called by `AgentLoop` before any tool runs. It receives `(tool_module, tool_args, context)` and returns the tool result. For special tools (`AskUser`, `RequestApproval`, `TeamSpawn`), this function gates execution.

**Current `team_spawn` branch in agent.ex (lines 2169-2178):**
```elixir
# If TeamSpawn succeeded, notify GenServer to track the child team
if tool_module == Loomkin.Tools.TeamSpawn do
  case result do
    {:ok, %{team_id: child_team_id}} ->
      send(agent_pid, {:child_team_spawned, child_team_id})
    _ ->
      :ok
  end
end
```

**Phase 9 expands this into a pre-spawn intercept.** The `team_spawn` branch now runs BEFORE `AgentLoop.default_run_tool/3`. The expanded sequence:

1. Pre-compute estimated cost from `tool_args["roles"]`
2. Check remaining budget via `GenServer.call(agent_pid, {:check_spawn_budget, estimated_cost})`
3. If budget exceeded → return `{:error, :budget_exceeded, %{remaining: ..., estimated: ...}}` immediately
4. If auto_approve_spawns is true → skip gate, proceed to spawn
5. Otherwise → publish `SpawnGateRequested` signal, register in Registry, block on `receive`
6. If approved → call `AgentLoop.default_run_tool/3` (the actual spawn), then track child team
7. If denied/timeout → return structured denial

### Pattern 2: Registry Blocking (established in Phase 6, replicated here)

**Registry key convention:**
```elixir
# Phase 6 used:
Registry.register(Loomkin.Teams.AgentRegistry, {:approval_gate, gate_id}, self())
# Phase 9 uses:
Registry.register(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id}, self())
```

**Blocking receive with timeout (5 minutes default):**
```elixir
receive do
  {:spawn_gate_response, ^gate_id, decision} ->
    Registry.unregister(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id})
    handle_spawn_decision(decision, tool_module, tool_args, context, agent_pid)
after
  timeout_ms ->
    Registry.unregister(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id})
    publish_spawn_gate_resolved(gate_id, agent_name, team_id, :timeout)
    {:ok, %{status: :denied, reason: :timeout, message: "Spawn gate timed out after #{div(timeout_ms, 1000)}s."}}
end
```

### Pattern 3: Agent State Struct Extension

**Add `auto_approve_spawns` field to defstruct (line 25-53 in agent.ex):**
```elixir
defstruct [
  # ... existing fields ...
  spawned_child_teams: [],
  auto_approve_spawns: false    # NEW: session-scoped, never persisted
]
```

**Toggle via `handle_call/cast`:**
```elixir
def handle_call({:set_auto_approve_spawns, enabled}, _from, state) do
  {:reply, :ok, %{state | auto_approve_spawns: enabled}}
end
```

**Read in `on_tool_execute` (the closure captures `state` at loop build time — but `auto_approve_spawns` can change during the session, so read via `GenServer.call(agent_pid, :get_spawn_settings)` to get fresh value).**

### Pattern 4: Budget Check via `CostTracker`

```elixir
# In agent.ex, new handle_call clause:
def handle_call({:check_spawn_budget, estimated_cost}, _from, state) do
  summary = CostTracker.team_cost_summary(state.team_id)
  spent =
    case summary[:total_cost_usd] do
      %Decimal{} = d -> Decimal.to_float(d)
      n when is_number(n) -> n
      _ -> 0.0
    end
  limit = roster_budget_limit(state)  # reads from session config or default $5.0
  remaining = limit - spent
  if remaining < estimated_cost do
    {:reply, {:budget_exceeded, %{remaining: remaining, estimated: estimated_cost}}, state}
  else
    {:reply, :ok, state}
  end
end
```

**Note:** `CostTracker.team_cost_summary/1` queries the DB (Ecto). This is called synchronously from the tool task process, not the GenServer. The GenServer `handle_call` wrapper ensures the read is safe but adds one round-trip. This is intentional — same approach as `check_ask_user_rate_limit`.

### Pattern 5: Cost Estimation from Roles

```elixir
@role_cost_estimates %{
  "researcher" => 0.20,
  "coder"      => 0.50,
  "reviewer"   => 0.30,
  "tester"     => 0.30,
  "lead"       => 0.50,
  "concierge"  => 0.10,
  "orienter"   => 0.10
}

defp estimate_spawn_cost(roles) when is_list(roles) do
  Enum.reduce(roles, 0.0, fn role_map, acc ->
    role = Map.get(role_map, "role") || Map.get(role_map, :role) || ""
    acc + Map.get(@role_cost_estimates, to_string(role), 0.20)
  end)
end
```

This logic can live in the agent module (private) or in a small helper module. Given Phase 6 kept approval logic inline in the tool, keeping cost estimation inline in agent.ex is consistent.

### Pattern 6: Pending Approval Distinguish via `type` Field

**Current `pending_approval` map shape (Phase 6):**
```elixir
%{
  gate_id: gate_id,
  question: question,
  timeout_ms: timeout_ms,
  started_at: started_at
}
```

**Phase 9 extends this with `type: :spawn_gate` and spawn-specific fields:**
```elixir
%{
  type: :spawn_gate,              # NEW: distinguishes from :checkpoint
  gate_id: gate_id,
  team_name: team_name,           # from tool_args
  roles: roles,                   # from tool_args — list of %{name, role}
  estimated_cost: estimated_cost, # float, precomputed
  limit_warning: nil | :depth | :agents,  # warning if 80%+ of limit
  timeout_ms: timeout_ms,
  started_at: started_at
}
```

**AgentCardComponent renders different content based on `pending_approval.type`:**
- `:spawn_gate` → shows team name, role composition, estimated cost, optional warning, auto-approve checkbox
- nil or `:checkpoint` → shows question text (Phase 6 current behavior)

### Pattern 7: Auto-Approve Checkbox — LiveView Event

**Checkbox in the spawn gate panel (HEEx template):**
```heex
<input
  type="checkbox"
  id={"auto-approve-spawns-#{@card.name}"}
  phx-click="toggle_auto_approve_spawns"
  phx-value-agent={@card.name}
  phx-value-enabled="true"
  class="..."
/>
<label for={"auto-approve-spawns-#{@card.name}"} class="...">
  Auto-approve future spawns
</label>
```

**workspace_live.ex handler:**
```elixir
def handle_event("toggle_auto_approve_spawns", %{"agent" => agent_name, "enabled" => enabled}, socket) do
  # Find agent pid via Registry and call set_auto_approve_spawns
  ...
  {:noreply, socket}
end
```

### Recommended File Touch List

```
lib/
├── loomkin/
│   ├── signals/
│   │   └── spawn.ex                    # NEW: SpawnGateRequested, SpawnGateResolved
│   ├── teams/
│   │   └── agent.ex                    # MODIFY: defstruct + on_tool_execute + handle_call
│   └── teams/
│       └── team_broadcaster.ex         # MODIFY: @critical_types add spawn gate types
└── loomkin_web/live/
    ├── workspace_live.ex               # MODIFY: handle_event + handle_info for spawn gate
    └── agent_card_component.ex         # MODIFY: spawn gate panel variant

test/
├── loomkin/
│   └── teams/
│       └── agent_spawn_gate_test.exs   # NEW: Wave 0 stubs for agent-side logic
└── loomkin_web/live/
    └── workspace_live_spawn_gate_test.exs  # NEW: Wave 0 stubs for LiveView handlers
```

### Anti-Patterns to Avoid

- **Modifying `TeamSpawn.run/2` directly:** The intercept belongs in `agent.ex` `on_tool_execute`. The tool itself stays clean.
- **Persisting `auto_approve_spawns` to DB:** Session-scoped means agent struct only. Do not add a DB migration.
- **Blocking the agent GenServer:** The `receive` loop must execute in the tool task process (the Task spawned by AgentLoop), not in `handle_call`. This is the established pattern — Phase 6 `RequestApproval.run/2` blocks in the Jido tool task, not the GenServer.
- **Querying team agent count at render time:** Pre-compute the 80% limit warning in the `on_tool_execute` intercept and embed in the `pending_approval` map. Do not query Manager from LiveView.
- **Using `send` instead of `GenServer.call` for budget check:** The budget check must read live agent state (`auto_approve_spawns`, current team budget). Use `GenServer.call` to read synchronously, same as `check_ask_user_rate_limit`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Routing response to blocking tool task | Custom PubSub or GenServer mailbox | `Registry` with `{:spawn_gate, gate_id}` key | Phase 6 established this exact pattern; Registry already contains the infrastructure |
| Countdown timer display | Custom JS hook | Existing `CountdownTimer` phx-hook | Already wired in Phase 6; `data-deadline-at` attribute drives it |
| Status transition on gate open/close | Manual status field writes | `set_status_and_broadcast/2` | Single point for status + signal emission; prevents duplicate broadcasts |
| Critical signal delivery | Batch-delayed signals | `@critical_types` MapSet in TeamBroadcaster | Spawn gate open/resolved must be sub-1-second, same as approval gate |
| Decimal cost math | Float arithmetic | `Decimal.to_float/1` on `total_cost_usd` | `CostTracker.team_cost_summary/1` returns `Decimal` from Ecto; workspace_live already has the conversion pattern |
| Three-button layout | New HEEx component | Copy approval panel structure from AgentCardComponent | Identical layout, just different content fields |

---

## Common Pitfalls

### Pitfall 1: Stale `auto_approve_spawns` from Closure Capture
**What goes wrong:** `build_loop_opts/1` captures `state` at the time the loop starts. If the user toggles auto-approve during a running session (between spawns), the closure still holds the old `state.auto_approve_spawns` value.
**Why it happens:** The `on_tool_execute` closure is built once in `build_loop_opts/1` and passed to `AgentLoop`. The loop doesn't rebuild it between iterations.
**How to avoid:** Do NOT read `state.auto_approve_spawns` from the closure-captured state. Instead, read it via `GenServer.call(agent_pid, :get_spawn_settings)` inside the closure — this always returns fresh agent state.
**Warning signs:** Auto-approve toggle has no effect until next agent restart.

### Pitfall 2: Budget Check Timing — DB vs. ETS
**What goes wrong:** `CostTracker.team_cost_summary/1` queries Ecto (DB-persisted task costs), while `RateLimiter` tracks in-memory ETS. The DB totals lag behind real-time token usage.
**Why it happens:** `team_cost_summary/1` aggregates `cost_usd` from `team_tasks` table, which is only written when a task completes via `persist_task_cost/3`. Real-time in-flight cost may not be reflected.
**How to avoid:** Accept this approximation — the CONTEXT.md decision uses `CostTracker.team_cost_summary` which is the same data the workspace UI already shows. Be explicit in the tool error message: "estimated remaining ~$X". Document in code that this is a DB-based estimate.
**Warning signs:** Budget check allows spawn when RateLimiter would have blocked.

### Pitfall 3: `pending_approval` Type Collision
**What goes wrong:** If a leader agent has both a checkpoint gate and a spawn gate open at the same time, the `pending_approval` map in the agent card is overwritten.
**Why it happens:** Agent card uses a single `pending_approval` key in its state.
**How to avoid:** Phase 9 must not open a spawn gate if `pending_approval` is already set. Add a guard in the intercept: if agent status is `:approval_pending`, deny the spawn immediately with a tool error rather than trying to queue a second gate.
**Warning signs:** One gate closes but the card still shows approval pending.

### Pitfall 4: Registry Cleanup on OTP Restart
**What goes wrong:** If the agent GenServer crashes while a spawn gate `receive` is blocking in the tool task process, the Registry entry for `{:spawn_gate, gate_id}` is cleaned up (process exits), but the gate_id may linger in workspace_live's `pending_approval` assigns.
**Why it happens:** workspace_live clears `pending_approval` only on `SpawnGateResolved` signal. If the gate task dies without publishing the resolved signal, the card stays in approval state.
**How to avoid:** In agent's `terminate/2`, if `status == :approval_pending`, publish a `SpawnGateResolved` signal with `outcome: :timeout` for any open gates. Check how Phase 6 handles this (it has the same exposure — worth inheriting the same cleanup pattern).
**Warning signs:** After agent crash, card permanently shows violet pulsing dot.

### Pitfall 5: Auto-Approve Checkbox Not Idempotent
**What goes wrong:** Checkbox renders with the default state (unchecked) but the agent's `auto_approve_spawns` is already true (e.g., if the auto-approve checkbox fires twice due to LiveView reconnect).
**Why it happens:** The checkbox is not bound to a LiveView assign — it's a one-way phx-click event, not a controlled input.
**How to avoid:** Pass `auto_approve_spawns` as a field in the `pending_approval` map so the card can render the checkbox in the correct checked/unchecked state. Alternatively, add an `auto_approve_spawns` assign to the agent card map, updated when the toggle fires.
**Warning signs:** Checkbox appears unchecked after page reload even though auto-approve is active.

### Pitfall 6: `pause_queued` Guard for `:approval_pending` Already Exists
**What goes good:** `handle_cast(:request_pause, %{status: :approval_pending} = state)` is already wired in agent.ex (line 745) to queue the pause. Phase 9 reuses `:approval_pending` status for spawn gates — the existing guard covers spawn gates for free.
**Confirmation:** No new state atom is needed. The queue-pause-during-approval behavior is already correct.

---

## Code Examples

### Minimal `on_tool_execute` Spawn Gate Intercept Shape

```elixir
# Source: agent.ex lines 2093-2182 (existing on_tool_execute pattern)
# Phase 9 expands the TeamSpawn branch BEFORE the existing post-success notify

# Inside the `else` branch (non-AskUser tools):
if tool_module == Loomkin.Tools.TeamSpawn do
  roles = Map.get(tool_args, "roles") || Map.get(tool_args, :roles) || []
  estimated_cost = estimate_spawn_cost(roles)

  case GenServer.call(agent_pid, {:check_spawn_budget, estimated_cost}) do
    {:budget_exceeded, details} ->
      AgentLoop.format_tool_result(
        {:error, :budget_exceeded, details}
      )

    :ok ->
      spawn_settings = GenServer.call(agent_pid, :get_spawn_settings)

      if spawn_settings.auto_approve_spawns do
        # Auto-approve path: skip gate, proceed directly
        result = AgentLoop.default_run_tool(tool_module, tool_args, context)
        notify_child_team_if_ok(result, agent_pid)
        result
      else
        # Human gate path: publish signal, block on receive
        gate_id = Ecto.UUID.generate()
        pending_info = build_spawn_pending(gate_id, tool_args, estimated_cost, ...)
        GenServer.call(agent_pid, {:open_spawn_gate, gate_id, pending_info})
        Registry.register(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id}, self())
        publish_spawn_gate_requested(pending_info)

        receive do
          {:spawn_gate_response, ^gate_id, %{outcome: :approved}} ->
            Registry.unregister(...)
            result = AgentLoop.default_run_tool(tool_module, tool_args, context)
            notify_child_team_if_ok(result, agent_pid)
            result
          {:spawn_gate_response, ^gate_id, %{outcome: :denied, reason: reason}} ->
            Registry.unregister(...)
            AgentLoop.format_tool_result({:ok, %{status: :denied, reason: :human_denied, message: reason}})
        after
          300_000 ->
            Registry.unregister(...)
            publish_spawn_gate_resolved(gate_id, :timeout)
            AgentLoop.format_tool_result({:ok, %{status: :denied, reason: :timeout, message: "Timed out."}})
        end
      end
else
  # non-TeamSpawn tools
  AgentLoop.default_run_tool(tool_module, tool_args, context)
end
```

### Signal Struct Shape (mirrors `Loomkin.Signals.Approval`)

```elixir
# Source: lib/loomkin/signals/approval.ex pattern
defmodule Loomkin.Signals.Spawn do
  defmodule GateRequested do
    use Jido.Signal,
      type: "agent.spawn.gate.requested",
      schema: [
        gate_id:        [type: :string, required: true],
        agent_name:     [type: :string, required: true],
        team_id:        [type: :string, required: true],
        team_name:      [type: :string, required: true],
        roles:          [type: {:list, :map}, required: true],
        estimated_cost: [type: :float, required: true],
        limit_warning:  [type: :atom, required: false],
        timeout_ms:     [type: :integer, required: false]
      ]
  end

  defmodule GateResolved do
    use Jido.Signal,
      type: "agent.spawn.gate.resolved",
      schema: [
        gate_id:    [type: :string, required: true],
        agent_name: [type: :string, required: true],
        team_id:    [type: :string, required: true],
        outcome:    [type: :atom, required: true]  # :approved | :denied | :timeout
      ]
  end
end
```

### `send_spawn_gate_response` in workspace_live.ex

```elixir
# Source: workspace_live.ex send_approval_response/2 pattern (lines 4452-4460)
defp send_spawn_gate_response(gate_id, decision) do
  case Registry.lookup(Loomkin.Teams.AgentRegistry, {:spawn_gate, gate_id}) do
    [{pid, _}] -> send(pid, {:spawn_gate_response, gate_id, decision})
    [] -> :ok
  end
end
```

### TeamBroadcaster `@critical_types` Addition

```elixir
# Source: lib/loomkin/teams/team_broadcaster.ex lines 33-44
# Add two new types to the existing MapSet:
@critical_types MapSet.new([
  "team.permission.request",
  "team.ask_user.question",
  "team.ask_user.answered",
  "team.child.created",
  "agent.error",
  "agent.approval.requested",
  "agent.approval.resolved",
  "agent.spawn.gate.requested",    # NEW
  "agent.spawn.gate.resolved",     # NEW
  # ... other existing types
])
```

### `pending_approval` Map with Spawn Gate Type

```elixir
# workspace_live.ex, handle_info for spawn gate requested:
pending_approval = %{
  type: :spawn_gate,
  gate_id: gate_id,
  team_name: sig.data.team_name,
  roles: sig.data.roles,
  estimated_cost: sig.data.estimated_cost,
  limit_warning: sig.data[:limit_warning],
  timeout_ms: sig.data[:timeout_ms] || 300_000,
  started_at: System.monotonic_time(:millisecond)
}
```

### AgentCardComponent Spawn Gate Panel (HEEx shape)

```heex
<%!-- Spawn gate panel — shown when pending_approval.type == :spawn_gate --%>
<div
  :if={@card.status == :approval_pending && @card[:pending_approval][:type] == :spawn_gate}
  class="border-t border-violet-500/30 bg-violet-950/20 px-4 py-3 flex flex-col gap-2"
>
  <div class="flex items-center justify-between gap-2">
    <span class="text-[11px] font-semibold text-violet-400">Spawn approval required</span>
    <span id={"countdown-#{@card.name}"} phx-hook="CountdownTimer"
          data-deadline-at={@card[:pending_approval][:started_at] + @card[:pending_approval][:timeout_ms]}
          class="text-[10px] font-mono text-violet-300/70 tabular-nums">--:--</span>
  </div>

  <%!-- Team name + role list + estimated cost --%>
  <p class="text-xs font-medium text-zinc-200">{@card[:pending_approval][:team_name]}</p>
  <%!-- roles rendered as "researcher x2, coder x1" --%>
  <p class="text-xs text-zinc-400">{format_roles(@card[:pending_approval][:roles])}</p>
  <p class="text-xs text-violet-300/80">estimated ~${Float.round(@card[:pending_approval][:estimated_cost], 2)}</p>

  <%!-- Optional limit warning --%>
  <p :if={@card[:pending_approval][:limit_warning]}
     class="text-xs text-amber-400">Approaching nesting depth limit</p>

  <%!-- Auto-approve checkbox --%>
  <label class="flex items-center gap-1.5 cursor-pointer text-[11px] text-zinc-400">
    <input type="checkbox" phx-click="toggle_auto_approve_spawns"
           phx-value-agent={@card.name} phx-value-enabled="true" />
    Auto-approve future spawns
  </label>

  <%!-- Three-button row (same as Phase 6) --%>
  ...approve/deny buttons...
</div>
```

---

## State of the Art

| Phase 6 (Checkpoint Gates) | Phase 9 (Spawn Gates) | Difference |
|---------------------------|----------------------|------------|
| `RequestApproval` tool calls `run/2` directly | Intercept in `on_tool_execute` before `default_run_tool` | Different intercept point — tool vs. pre-tool |
| Registry key: `{:approval_gate, gate_id}` | Registry key: `{:spawn_gate, gate_id}` | Different key namespace |
| `pending_approval` has no `type` field | `pending_approval.type = :spawn_gate` | Type discriminator needed |
| No budget check | Budget check always runs before gate | New: budget-exceeds path returns error, no gate shown |
| No auto-approve | `auto_approve_spawns` field on agent state | New: skips gate when true |
| Card shows plain question text | Card shows team name, roles, cost, warning | Richer content |
| Signal: `agent.approval.requested/resolved` | Signal: `agent.spawn.gate.requested/resolved` | Separate signal types for clean routing |

---

## Open Questions

1. **Budget limit source for the agent-side check**
   - What we know: `CostTracker.team_cost_summary/1` returns DB-persisted cost. workspace_live uses `roster_budget/1` which hardcodes `limit: 5.0` when no session config is present.
   - What's unclear: Does the budget limit come from a session-level setting, a team config, or always $5.00? The agent's `handle_call` for budget check needs to know the limit value.
   - Recommendation: Read the limit from the same source as `roster_budget/1` — if there's a session or team config, use it; otherwise default $5.00. This may require passing the budget limit into agent opts at start_link time, or querying the same DB table workspace_live uses.

2. **Limit warning: agent count check**
   - What we know: `@default_max_nesting_depth 2` is enforced in `Manager.create_sub_team/3`. Max-agents-per-team is not currently enforced.
   - What's unclear: Is there a `max_agents_per_team` config constant that Phase 9 can read to compute the 80% threshold? Or does the planner need to define this constant?
   - Recommendation: Define a `@default_max_agents_per_team` constant (e.g., 10) in `Manager` mirroring `@default_max_nesting_depth`. The warning threshold is 80% of that value (8 agents). Count agents via `Registry` or `Manager` at gate-open time.

3. **Auto-approve checkbox state across multiple gates**
   - What we know: The CONTEXT says the checkbox appears on the first spawn gate. Toggling enables auto-approve for the rest of the session.
   - What's unclear: Should the checkbox appear on every gate (reflecting current auto_approve_spawns state), or only on the first gate? If on every gate, how does it show the current state (checked/unchecked)?
   - Recommendation: Show checkbox on every spawn gate card. Pass `auto_approve_spawns` value as a field in the `pending_approval` map (sourced from the signal or from agent state read at gate-open time). The checkbox renders as checked if already enabled.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin/teams/agent_spawn_gate_test.exs test/loomkin_web/live/workspace_live_spawn_gate_test.exs` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TREE-03 | Budget check blocks spawn when remaining < estimated | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | Spawn gate opens and blocks tool task until approved | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | Spawn gate timeout auto-denies with structured result | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | Auto-approve skips gate when within budget | unit | `mix test test/loomkin/teams/agent_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | `approve_spawn` event routes decision to blocking tool task via Registry | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | `deny_spawn` event routes denial to blocking tool task | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | SpawnGateRequested signal sets `pending_approval` on agent card | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | SpawnGateResolved signal clears `pending_approval` from agent card | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start` | ❌ Wave 0 |
| TREE-03 | TeamBroadcaster classifies spawn gate signal types as critical | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs --no-start` | ✅ (modify existing) |
| TREE-03 | `toggle_auto_approve_spawns` event updates agent state | unit | `mix test test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/teams/agent_spawn_gate_test.exs test/loomkin_web/live/workspace_live_spawn_gate_test.exs --no-start`
- **Per wave merge:** `mix test --no-start`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin/teams/agent_spawn_gate_test.exs` — covers budget check, gate open/close, auto-approve, timeout behaviors
- [ ] `test/loomkin_web/live/workspace_live_spawn_gate_test.exs` — covers handle_event approve/deny/toggle and handle_info SpawnGateRequested/Resolved
- [ ] `lib/loomkin/signals/spawn.ex` — required by tests (will fail with UndefinedFunctionError until created in Wave 1)
- Modify existing `test/loomkin/teams/team_broadcaster_test.exs` — add assertions for spawn gate signal types in `@critical_types`

**Test style reference:** Follow `test/loomkin_web/live/workspace_live_approval_test.exs` — `ExUnit.Case, async: true`, build minimal Phoenix.LiveView.Socket directly in helpers, use `Registry.register` to simulate blocking tool task process, use `assert_receive` for message routing assertions.

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection of `lib/loomkin/tools/request_approval.ex` — complete blocking tool pattern
- Direct code inspection of `lib/loomkin/teams/agent.ex` (on_tool_execute, defstruct, set_status_and_broadcast)
- Direct code inspection of `lib/loomkin/teams/cost_tracker.ex` — `team_cost_summary/1` signature and return shape
- Direct code inspection of `lib/loomkin/teams/team_broadcaster.ex` — `@critical_types` MapSet
- Direct code inspection of `lib/loomkin_web/live/agent_card_component.ex` — approval panel HEEx and status helpers
- Direct code inspection of `lib/loomkin_web/live/workspace_live.ex` — `send_approval_response`, `roster_budget`, event handlers
- Direct code inspection of `lib/loomkin/teams/manager.ex` — `@default_max_nesting_depth 2`
- Direct code inspection of `lib/loomkin/signals/approval.ex` — Jido.Signal struct pattern
- Direct code inspection of `test/loomkin_web/live/workspace_live_approval_test.exs` — test style and socket builder pattern
- Direct code inspection of `.planning/phases/09-spawn-safety/09-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence)
- Phase 6 PLAN.md (06-01-PLAN.md) — confirmed Wave 0 stub pattern and test file naming conventions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all modules verified by direct code inspection
- Architecture: HIGH — Phase 6 pattern is fully implemented and tested; Phase 9 is a direct extension
- Pitfalls: HIGH — derived from direct analysis of existing code structure; Pitfall 1 (stale closure) is a real implementation trap visible in the agent.ex code

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable Elixir/Phoenix/OTP patterns, internal code only)
