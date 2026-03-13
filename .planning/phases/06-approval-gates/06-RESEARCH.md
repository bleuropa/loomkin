# Phase 6: Approval Gates - Research

**Researched:** 2026-03-08
**Domain:** Elixir GenServer state machines, Jido tool authoring, Phoenix LiveView UI patterns, countdown timers
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Approval Card Placement & Design**
- Approval gate UI lives on the **agent card** — the card expands in-place to show a full approval panel (question, action buttons, countdown). Card grows vertically, stays in the grid.
- **Purple/violet accent** distinguishes approval gates from permission hooks (amber). Purple border or header strip on the expanded card section.
- Action buttons: **Approve / Deny / Approve w/ Context** — three discrete buttons.
  - Approve: one-click, no text required.
  - Approve w/ Context: reveals a text field for optional guidance to the agent.
  - Deny: offers optional denial reason text field.
- The agent receives the human's text (if any) along with the approval/denial decision in its resumed context.

**Leader Team-Wide Banner**
- When an agent with the **existing 'lead' role** hits an approval gate, a persistent banner appears **above the agent card grid** (below the workspace header).
- Banner is **informational only** — workspace stays fully interactive. Other agents keep running, human can still interact with non-leader cards.
- Banner text: something like "Team leader awaiting your approval — team progress depends on this."
- Banner includes the countdown timer, matching the card.
- Banner disappears when the gate is resolved (approved, denied, or timed out).

**Timeout Behavior**
- **Default timeout: 5 minutes** — configurable globally (app config) and overridable per-gate via `RequestApproval` args.
- **Visible countdown timer** displayed on the expanded approval card section and on the leader banner (when applicable).
- On timeout: gate **auto-denies**. Agent receives a structured timeout reason:
  `{status: :denied, reason: :timeout, message: "Approval gate timed out after N minutes. Human did not respond."}`.
- The agent can use the timeout reason to decide whether to retry, proceed without approval, or surface an error.

**Approval Context Depth**
- The expanded card shows: **agent name, the question text, and one line of 'what the agent is about to do'** (from the RequestApproval context). Clean, scannable — enough to decide without being overwhelmed.
- **`RequestApproval` tool API**: `RequestApproval(question: "...", timeout: 300)` — question is required (shown to human), timeout is optional (defaults to global default).
- **Comms feed events**: approval gate surfaces in the comms feed with purple styling.
  - Request event: "Agent X is requesting approval: [question]"
  - Resolution event: "Approval gate approved/denied by human" or "Approval gate timed out"
- Both open and close events appear in the feed for a full timeline record.

### Claude's Discretion
- Exact purple/violet color value (consistent with brand palette)
- Countdown timer visual design (ring, bar, or text-only)
- Leader banner height, typography, and exact copy
- Positioning of Approve / Deny / Approve w/ Context buttons on the card
- Whether the expanded card uses a collapsible header or always-expanded layout
- Text field placeholder copy for optional Approve w/ Context and Deny reason fields
- Comms event icon/color for approval_gate type vs. other event types

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTV-02 | Approval gates where agents pause at critical junctures and await human sign-off (distinct signal type from permission hooks) | `RequestApproval` Jido Action tool, `Agent.handle_call(:approval_response)` GenServer handler, `ApprovalRequested`/`ApprovalResolved` signal types, `agent-card-blocked` class already hooks to `:approval_pending` state, countdown via `Process.send_after` |
</phase_requirements>

---

## Summary

Phase 6 is primarily an integration and extension task, not greenfield work. The Elixir/OTP infrastructure (`Agent` GenServer, Jido Signal Bus, `TeamBroadcaster`, `set_status_and_broadcast`) is fully established from prior phases. The `:approval_pending` status atom already exists in `AgentCardComponent` card state class dispatching, the status dot helper, and the `handle_cast(:request_pause, ...)` guard — the scaffolding was pre-wired in Phase 5.

The primary work falls into five bounded sub-domains: (1) a new `RequestApproval` Jido Action tool that blocks inside the AgentLoop task until it receives an answer via Registry-based message routing (mirroring `AskUser` exactly); (2) new `Agent` GenServer handlers (`handle_call(:approval_response)` and `handle_info(:approval_timeout)`) that transition the agent through `:approval_pending` and back; (3) two new signal types (`ApprovalRequested`, `ApprovalResolved`) published on the Jido bus and classified as critical in `TeamBroadcaster`; (4) an expanded `:approval_pending` section in `AgentCardComponent` with purple accent, three-button layout, countdown timer, and optional text fields; and (5) a workspace-level leader banner and `handle_event`/`handle_info` plumbing in `workspace_live.ex`.

The `AskUser` tool is the canonical model for the blocking pattern: publish a signal, register the calling PID in `AgentRegistry` under a keyed entry, then block on `receive` with an `after` clause for timeout. The approval gate uses the same mechanism but the response carries structured `{status, reason, message, context}` data instead of a bare answer string.

**Primary recommendation:** Model `RequestApproval` directly on `AskUser`; model `Agent.handle_call(:approval_response)` directly on `handle_cast(:permission_response, ...)`; model the leader banner as a conditional `assign` in workspace_live keyed off `agent.role == :lead` when an `ApprovalRequested` signal arrives.

---

## Standard Stack

### Core (all already in the project — no new deps needed)

| Library/Module | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Jido.Action | existing | `RequestApproval` tool definition + validation | All agent tools use this; NimbleOptions schema validation is automatic |
| Jido.Signal (use macro) | existing | `ApprovalRequested` / `ApprovalResolved` signal structs | All signals in `lib/loomkin/signals/` use this pattern |
| GenServer (`Agent`) | OTP 27 | `handle_call(:approval_response)`, `handle_info(:approval_timeout)` | Established state machine throughout the agent |
| Process.send_after | OTP stdlib | Countdown timeout — `Process.send_after(self(), :approval_timeout, timeout_ms)` | Used by `AgentWatcher` (crash recovery timer) and implicitly by many comms patterns |
| Registry (AgentRegistry) | OTP stdlib | Route approval response back to blocking tool task | Exact pattern used by `AskUser` tool: register under `{:approval_gate, gate_id}` |
| Phoenix LiveView assigns | existing | Leader banner state (`@leader_approval_pending` assign) | Standard workspace_live assign pattern |
| Tailwind CSS | existing | Purple/violet card expansion styling | All card styling uses Tailwind utility classes |

### No New Dependencies Required

This phase adds zero new hex packages. Every mechanism it needs — blocking tool tasks, Registry-keyed message routing, Jido Signal publishing, GenServer state transitions, LiveView assigns, countdown timers — is already present and battle-tested in the codebase.

---

## Architecture Patterns

### Recommended File Structure (new files only)

```
lib/loomkin/tools/request_approval.ex          # New: RequestApproval Jido Action
lib/loomkin/signals/approval.ex                # New: ApprovalRequested + ApprovalResolved signals
```

Existing files to modify:
```
lib/loomkin/teams/agent.ex                     # New GenServer handlers
lib/loomkin/teams/team_broadcaster.ex          # Add critical_types entries
lib/loomkin_web/live/workspace_live.ex         # handle_event + handle_info + leader banner
lib/loomkin_web/live/agent_card_component.ex   # Expand :approval_pending branch
lib/loomkin_web/live/agent_comms_component.ex  # Add approval_gate type_config entries
lib/loomkin/tools/registry.ex                  # Register RequestApproval, add param atoms
```

---

### Pattern 1: Blocking Tool with Registry-Keyed Response Routing

This is the **exact pattern used by `AskUser`** (`lib/loomkin/tools/ask_user.ex`). `RequestApproval` follows it without deviation.

**What:** A Jido Action tool runs in a Task (under `TaskSupervisor`). It publishes a signal, registers `self()` in the AgentRegistry under a unique key, then blocks with `receive`/`after`. The LiveView handler finds the PID via Registry lookup and sends the response message directly to it. The `after` clause fires the timeout behavior.

**When to use:** Any time an agent must pause its loop and await an external event before continuing.

**Example (based on AskUser, adapted for approval gate):**
```elixir
# lib/loomkin/tools/request_approval.ex
defmodule Loomkin.Tools.RequestApproval do
  use Jido.Action,
    name: "request_approval",
    description: "...",
    schema: [
      question: [type: :string, required: true],
      timeout:  [type: :integer, required: false]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  @default_timeout_ms 300_000  # 5 minutes — matches locked decision

  def run(params, context) do
    team_id    = param!(context, :team_id)
    agent_name = param!(context, :agent_name)
    question   = param!(params, :question)
    timeout    = param(params, :timeout)
    timeout_ms = if timeout, do: timeout * 1_000, else: @default_timeout_ms

    gate_id = Ecto.UUID.generate()
    Registry.register(Loomkin.Teams.AgentRegistry, {:approval_gate, gate_id}, self())

    # Publish ApprovalRequested signal (critical — bypasses 50ms batch window)
    Loomkin.Signals.Approval.Requested.new!(%{
      gate_id: gate_id,
      agent_name: agent_name,
      team_id: team_id,
      question: question,
      timeout_ms: timeout_ms
    })
    |> Loomkin.Signals.publish()

    receive do
      {:approval_response, ^gate_id, decision} ->
        Registry.unregister(Loomkin.Teams.AgentRegistry, {:approval_gate, gate_id})
        format_result(decision)
    after
      timeout_ms ->
        Registry.unregister(Loomkin.Teams.AgentRegistry, {:approval_gate, gate_id})

        # Publish ApprovalResolved signal (timeout)
        Loomkin.Signals.Approval.Resolved.new!(%{
          gate_id: gate_id,
          agent_name: agent_name,
          team_id: team_id,
          outcome: :timeout
        })
        |> Loomkin.Signals.publish()

        {:ok, %{
          status: :denied,
          reason: :timeout,
          message: "Approval gate timed out. Human did not respond.",
          context: nil
        }}
    end
  end

  defp format_result(%{outcome: :approved, context: ctx}) do
    {:ok, %{status: :approved, reason: nil, message: "Approved by human.", context: ctx}}
  end
  defp format_result(%{outcome: :denied, reason: reason, context: ctx}) do
    {:ok, %{status: :denied, reason: :denied, message: reason || "Denied by human.", context: ctx}}
  end
end
```

---

### Pattern 2: Agent Status Transition to `:approval_pending`

**What:** When `ApprovalRequested` signal arrives at `workspace_live`, it sets the agent card assign to show the approval panel. The agent itself **does not change its GenServer status** to `:approval_pending` via `set_status_and_broadcast` — the blocking happens inside the AgentLoop Task (the `receive` in the tool), so from the GenServer's perspective the agent is still `:working`. The card UI uses the signal to overlay the approval panel without needing a GenServer status change.

**Key insight:** `:approval_pending` is a UI-level state overlaid on the card when an `ApprovalRequested` signal arrives for that agent. The agent GenServer continues running (the tool task is blocking, not the GenServer). This is how `AskUser` works too — the agent doesn't change to a "pending question" status; the LiveView just shows the overlay from the signal.

**Variant — if GenServer status IS needed** (e.g., to make `handle_cast(:request_pause)` guard work): The pre-wired `handle_cast(:request_pause, %{status: :approval_pending})` guard in `agent.ex` already handles queuing — but it only fires if the status is set. If we keep it purely UI-level, that guard is dead code during Phase 6 and should be left in place for future use.

**Recommendation for Phase 6:** Keep it UI-only (signal-driven card overlay) to match AskUser's pattern. The `:approval_pending` GenServer status can be used in a future phase if deeper state machine integration is needed. The existing guard in `agent.ex` is harmless and stays.

---

### Pattern 3: workspace_live Event and Signal Handlers

**What:** Two new `handle_event` clauses handle button clicks from the expanded approval card. Two new `handle_info` clauses process incoming signals from `TeamBroadcaster`. A leader banner assign is toggled when the approving agent has `:lead` role.

```elixir
# In workspace_live.ex — new handle_event clauses

def handle_event("approve_card_agent", %{"gate-id" => gate_id, "agent" => agent_name,
    "context" => ctx}, socket) do
  send_approval_response(gate_id, %{outcome: :approved, context: ctx})
  {:noreply, clear_approval_state(socket, gate_id)}
end

def handle_event("deny_card_agent", %{"gate-id" => gate_id, "agent" => _agent_name,
    "reason" => reason}, socket) do
  send_approval_response(gate_id, %{outcome: :denied, reason: reason, context: nil})
  {:noreply, clear_approval_state(socket, gate_id)}
end

# New handle_info for ApprovalRequested signal
def handle_info(%Jido.Signal{type: "agent.approval.requested"} = sig, socket) do
  # Set card to approval_pending; set leader banner if role == :lead
  ...
end

# New handle_info for ApprovalResolved signal
def handle_info(%Jido.Signal{type: "agent.approval.resolved"} = sig, socket) do
  # Clear approval_pending from card; clear leader banner
  ...
end

# Helper — routes response back to blocking tool task
defp send_approval_response(gate_id, decision) do
  case Registry.lookup(Loomkin.Teams.AgentRegistry, {:approval_gate, gate_id}) do
    [{pid, _}] -> send(pid, {:approval_response, gate_id, decision})
    [] -> :ok
  end
end
```

---

### Pattern 4: Signal Type Definitions

Model directly on `Loomkin.Signals.Agent` / `Loomkin.Signals.Team`. New module: `lib/loomkin/signals/approval.ex`.

```elixir
defmodule Loomkin.Signals.Approval do
  defmodule Requested do
    use Jido.Signal,
      type: "agent.approval.requested",
      schema: [
        gate_id:    [type: :string, required: true],
        agent_name: [type: :string, required: true],
        team_id:    [type: :string, required: true],
        question:   [type: :string, required: true],
        timeout_ms: [type: :integer, required: false]
      ]
  end

  defmodule Resolved do
    use Jido.Signal,
      type: "agent.approval.resolved",
      schema: [
        gate_id:    [type: :string, required: true],
        agent_name: [type: :string, required: true],
        team_id:    [type: :string, required: true],
        outcome:    [type: :atom, required: true]  # :approved | :denied | :timeout
      ]
  end
end
```

Both signal types must be added to `@critical_types` in `TeamBroadcaster` so they bypass the 50ms batch window and are delivered immediately to LiveView.

---

### Pattern 5: Countdown Timer in LiveView

**What:** The countdown display is a client-side concern. The server pushes the `timeout_ms` value to the card via assigns. A lightweight JavaScript hook (or pure CSS animation with `animation-duration`) drives the visual countdown without server round-trips.

**Recommended approach:** Use a Phoenix LiveView JS hook named `"CountdownTimer"` that reads `data-timeout-ms` and `data-started-at` attributes, updates a text or progress indicator every second via `requestAnimationFrame` or `setInterval`. The hook self-destructs when the element is removed from DOM (approval resolved).

**Alternative (simpler, text-only):** Push a `Process.send_after(self(), {:approval_tick, gate_id}, 1000)` loop from workspace_live. Each tick pushes a new `seconds_remaining` assign to the component. Simple, no JS, but adds server traffic per gate per second. Given that gates are rare events (not continuous), this is acceptable.

**Recommendation:** Use the JS hook approach (zero server traffic, no extra handle_info clauses). The project already uses JS hooks (e.g., `CommsFeedScroll` with `MutationObserver`). A minimal `CountdownTimer` hook in `assets/js/app.js` is ~20 lines.

---

### Pattern 6: AgentCardComponent Approval Panel

**What:** When `@card.status == :approval_pending` (set by workspace_live when the signal arrives), an expanded panel section is conditionally rendered inside the card `<div>`. The panel overlays or extends the card similarly to `pending_question` (the existing question overlay uses `absolute inset-0`).

**Key decision (Claude's discretion):** Use an always-visible in-card expansion (not absolute overlay) so the card grows vertically. This matches the locked decision "card grows vertically, stays in the grid." Unlike `pending_question` which uses `absolute inset-0`, the approval panel should be a bottom extension.

```heex
<%!-- Approval gate panel (always-expanded, appended below content area) --%>
<div
  :if={@card.status == :approval_pending && @card[:pending_approval]}
  class="mt-3 rounded-lg p-3 border"
  style="border-color: #7c3aed40; background: #7c3aed08;"
>
  <div class="flex items-center gap-2 mb-2">
    <%!-- Purple indicator strip --%>
    <div class="w-1 h-full rounded-full" style="background: #7c3aed;" />
    <span class="text-xs font-semibold text-violet-400">Approval required</span>
    <%!-- Countdown --%>
    <span
      class="ml-auto text-[10px] font-mono text-violet-300/60"
      phx-hook="CountdownTimer"
      id={"countdown-#{@card[:pending_approval][:gate_id]}"}
      data-timeout-ms={@card[:pending_approval][:timeout_ms]}
      data-started-at={@card[:pending_approval][:started_at]}
    >5:00</span>
  </div>

  <p class="text-sm text-gray-200 mb-3 leading-relaxed">
    {@card[:pending_approval][:question]}
  </p>

  <%!-- Three-button row --%>
  <div class="flex flex-wrap gap-2">
    <button
      phx-click="approve_card_agent"
      phx-value-gate-id={@card[:pending_approval][:gate_id]}
      phx-value-agent={@card.name}
      phx-value-context=""
      class="px-3 py-1.5 text-xs font-medium rounded text-violet-200
             bg-violet-600/20 border border-violet-500/30 hover:bg-violet-600/40 cursor-pointer"
    >
      Approve
    </button>
    <button
      phx-click={JS.toggle(to: "#approve-ctx-#{@card.name}")}
      class="px-3 py-1.5 text-xs font-medium rounded text-violet-200
             bg-violet-600/10 border border-violet-500/20 hover:bg-violet-600/30 cursor-pointer"
    >
      Approve w/ Context
    </button>
    <button
      phx-click={JS.toggle(to: "#deny-ctx-#{@card.name}")}
      class="px-3 py-1.5 text-xs font-medium rounded text-rose-300
             bg-rose-900/20 border border-rose-700/30 hover:bg-rose-900/40 cursor-pointer"
    >
      Deny
    </button>
  </div>

  <%!-- Approve w/ Context text input (hidden by default) --%>
  <div id={"approve-ctx-#{@card.name}"} class="hidden mt-2">
    <form phx-submit="approve_card_agent">
      <input type="hidden" name="gate-id" value={@card[:pending_approval][:gate_id]} />
      <input type="hidden" name="agent" value={@card.name} />
      <textarea name="context" rows="2" placeholder="Optional guidance for the agent..."
        class="w-full text-xs bg-zinc-900 border border-violet-500/20 rounded p-2 text-gray-200
               focus:outline-none focus:border-violet-500/60 resize-none" />
      <button type="submit"
        class="mt-1.5 px-3 py-1 text-xs font-medium rounded text-violet-200
               bg-violet-600/20 border border-violet-500/30 cursor-pointer">
        Approve
      </button>
    </form>
  </div>

  <%!-- Deny reason text input (hidden by default) --%>
  <div id={"deny-ctx-#{@card.name}"} class="hidden mt-2">
    <form phx-submit="deny_card_agent">
      <input type="hidden" name="gate-id" value={@card[:pending_approval][:gate_id]} />
      <input type="hidden" name="agent" value={@card.name} />
      <textarea name="reason" rows="2" placeholder="Optional reason for denial..."
        class="w-full text-xs bg-zinc-900 border border-rose-700/30 rounded p-2 text-gray-200
               focus:outline-none focus:border-rose-700/60 resize-none" />
      <button type="submit"
        class="mt-1.5 px-3 py-1 text-xs font-medium rounded text-rose-300
               bg-rose-900/20 border border-rose-700/30 cursor-pointer">
        Deny
      </button>
    </form>
  </div>
</div>
```

---

### Pattern 7: Leader Banner in workspace_live.ex

**What:** A conditional block rendered when `@leader_approval_pending` assign is set. Uses `send_update` is NOT needed — the banner is a simple workspace-level assign toggled by `handle_info` for `ApprovalRequested` / `ApprovalResolved`.

```heex
<%!-- Leader approval banner (above agent grid, below workspace header) --%>
<div
  :if={@leader_approval_pending}
  class="mx-4 mb-3 px-4 py-2.5 rounded-lg border flex items-center gap-3"
  style="border-color: #7c3aed40; background: #7c3aed10;"
>
  <div class="w-2 h-2 rounded-full bg-violet-500 animate-pulse flex-shrink-0" />
  <span class="text-sm text-violet-300 flex-1">
    Team leader awaiting your approval — team progress depends on this.
  </span>
  <span
    class="text-xs font-mono text-violet-400/60"
    phx-hook="CountdownTimer"
    id="leader-banner-countdown"
    data-timeout-ms={@leader_approval_pending[:timeout_ms]}
    data-started-at={@leader_approval_pending[:started_at]}
  >
    5:00
  </span>
</div>
```

---

### Anti-Patterns to Avoid

- **Blocking the GenServer:** Never block `handle_call` or `handle_info` waiting for the human response. The tool blocks in its Task process — the GenServer stays responsive.
- **Using `handle_cast` for the response routing:** Approval response is time-sensitive. Use a direct `Registry.lookup` + `send/2` in the LiveView handler — same as `send_ask_user_answer/2`.
- **Setting `:approval_pending` as a GenServer status via `set_status_and_broadcast`:** This would emit an `agent.status` signal which would confuse the status machine guards. Keep approval state UI-only, driven by `ApprovalRequested` signal.
- **Running countdown timer on the server:** Even though simple, a per-second `send_after` loop per gate adds unnecessary load. Use the JS hook.
- **Forgetting to unregister in ALL exit paths:** The `receive` block in `RequestApproval.run/2` must unregister from the Registry in both the response branch and the `after` branch, and also handle the case where the LiveView disappears (the tool task will eventually time out via `after`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Blocking tool with response routing | Custom async channel | Registry-keyed `receive` + `send` (AskUser pattern) | Already proven; handles concurrency safely |
| Signal struct definition | Map/plain struct | `use Jido.Signal` macro | Handles `new!/1` validation, bus publishing, schema |
| Countdown timer state | Server-side `send_after` tick loop | JS hook with `setInterval` | Zero server traffic; self-cleaning on DOM removal |
| Role detection for leader banner | New field on agent | `agent.role == :lead` check in workspace signal handler | Role is already in card assigns and registry metadata |
| Timeout mechanism | Custom GenServer timer | `Process.send_after` in the tool task via `receive after` clause | The `after` clause in OTP `receive` IS the timeout mechanism |

---

## Common Pitfalls

### Pitfall 1: Timeout Fires but LiveView Already Dismissed the Card
**What goes wrong:** Human navigates away. The approval gate times out. `ApprovalResolved` signal fires. But the LiveView socket is already gone — no crash, just a silent no-op.
**Why it happens:** The Registry entry points to the tool task PID, which is valid even after socket disconnect. The tool times out correctly. The resolved signal goes to a dead LiveView subscriber.
**How to avoid:** TeamBroadcaster handles dead subscribers via `Process.monitor` and removes them. No special handling needed. The signal gets delivered to zero subscribers — this is correct behavior.
**Warning signs:** N/A — this is the intended behavior.

### Pitfall 2: Double Registration for Same Gate
**What goes wrong:** If `RequestApproval.run/2` is called twice for the same `gate_id` (impossible under normal conditions, but worth noting), `Registry.register` returns `{:error, {:already_registered, _}}`.
**Why it happens:** UUIDs from `Ecto.UUID.generate()` prevent this. Not a real risk, but guard with a unique key per call.
**How to avoid:** Always use `Ecto.UUID.generate()` for `gate_id`. Do not share gate IDs across invocations.

### Pitfall 3: Card Shows Approval Panel After Resolution
**What goes wrong:** Signal delivery ordering: `ApprovalResolved` arrives at workspace_live *before* the card assign is cleared.
**Why it happens:** Normally resolved signal arrives after the LiveView event handler clears the state. But if the tool times out (no LiveView interaction), the `ApprovalResolved` signal must clear the UI.
**How to avoid:** Handle `ApprovalResolved` in a `handle_info` clause that clears `@pending_approvals` and `@leader_approval_pending` by `gate_id`. Both `handle_event` (user action) and `handle_info` (timeout) must clear.

### Pitfall 4: `pending_approval` Card Assign Structure
**What goes wrong:** The card assign that carries `gate_id`, `question`, `timeout_ms`, `started_at` must be present on the specific agent's card struct before `AgentCardComponent` can render the approval panel.
**Why it happens:** workspace_live aggregates agent cards as maps. Adding `pending_approval` to the card map must happen in the same place where other card fields are set (the roster/card update path).
**How to avoid:** When handling `ApprovalRequested` signal in workspace_live, `update_card/3` (or equivalent) the specific agent's card map with `pending_approval: %{gate_id: ..., question: ..., timeout_ms: ..., started_at: System.monotonic_time(:millisecond)}`.

### Pitfall 5: Leader Role Identification
**What goes wrong:** The leader banner should only appear when the approving agent has role `:lead`. Role data is available in the Registry metadata (`%{role: ..., status: ..., model: ...}`) and in `socket.assigns.cards` (each card has a `:role` field).
**Why it happens:** The signal only carries `agent_name` and `team_id`, not the role. Workspace_live must look up the role from the card assigns or Registry.
**How to avoid:** In the `ApprovalRequested` handler, look up `socket.assigns.cards[agent_name][:role]` to determine if leader banner should be shown. This is always available since cards are fully populated before this signal can arrive.

### Pitfall 6: JS Hook Cleanup
**What goes wrong:** A `CountdownTimer` hook element is removed from DOM (approval resolved) but the hook's `setInterval` keeps ticking, trying to update a non-existent element.
**Why it happens:** JS hooks need explicit cleanup in their `destroyed()` callback.
**How to avoid:** In the `CountdownTimer` hook, store the interval ID and call `clearInterval(this.intervalId)` in the `destroyed()` callback. Phoenix LiveView calls `destroyed()` when the element is removed from DOM.

---

## Code Examples

Verified patterns from existing codebase:

### AskUser — canonical blocking tool pattern
```elixir
# Source: lib/loomkin/tools/ask_user.ex
Registry.register(Loomkin.Teams.AgentRegistry, {:ask_user, question_id}, caller)
signal = Loomkin.Signals.Team.AskUserQuestion.new!(%{...})
Loomkin.Signals.publish(%{signal | data: Map.put(signal.data, :options, options)})

receive do
  {:ask_user_answer, ^question_id, answer} ->
    Registry.unregister(Loomkin.Teams.AgentRegistry, {:ask_user, question_id})
    {:ok, %{result: "User answered: #{answer}", answer: answer}}
after
  300_000 ->
    Registry.unregister(Loomkin.Teams.AgentRegistry, {:ask_user, question_id})
    {:ok, %{result: "Question timed out after 5 minutes. No answer received.", answer: nil}}
end
```

### send_ask_user_answer — canonical Registry-based response routing
```elixir
# Source: lib/loomkin_web/live/workspace_live.ex
defp send_ask_user_answer(question_id, answer) do
  case Registry.lookup(Loomkin.Teams.AgentRegistry, {:ask_user, question_id}) do
    [{pid, _}] -> send(pid, {:ask_user_answer, question_id, answer})
    [] -> :ok
  end
end
```

### set_status_and_broadcast — agent status transition + signal
```elixir
# Source: lib/loomkin/teams/agent.ex
defp set_status_and_broadcast(state, new_status) do
  if state.status == new_status do
    state
  else
    previous_status = state.status
    state = set_status(state, new_status)
    broadcast_team(
      state,
      {:agent_status, state.name, new_status,
       %{previous_status: previous_status, pause_queued: state.pause_queued}}
    )
    ...
  end
end
```

### TeamBroadcaster @critical_types — where to add approval signal types
```elixir
# Source: lib/loomkin/teams/team_broadcaster.ex
@critical_types MapSet.new([
  "team.permission.request",
  "team.ask_user.question",
  "team.ask_user.answered",
  "agent.error",
  "agent.escalation",
  "team.dissolved",
  "collaboration.peer.message",
  "agent.crashed",
  "agent.recovered",
  "agent.permanently_failed"
  # ADD: "agent.approval.requested"
  # ADD: "agent.approval.resolved"
])
```

### AgentCommsComponent @type_config — where to add approval_gate entry
```elixir
# Source: lib/loomkin_web/live/agent_comms_component.ex
# Existing example for reference — decision type uses violet/purple
decision: %{
  icon: "🧠",
  accent_border: "rgba(167, 139, 250, 0.35)",
  accent_text: "#c4b5fd",
  accent_bg: "rgba(167, 139, 250, 0.10)"
}
# Add:
approval_gate_requested: %{
  icon: "🔐",
  accent_border: "rgba(124, 58, 237, 0.40)",
  accent_text: "#a78bfa",
  accent_bg: "rgba(124, 58, 237, 0.12)"
},
approval_gate_resolved: %{
  icon: "✔",
  accent_border: "rgba(124, 58, 237, 0.30)",
  accent_text: "#8b5cf6",
  accent_bg: "rgba(124, 58, 237, 0.08)"
}
```

### Existing card_state_class — :approval_pending already handled
```elixir
# Source: lib/loomkin_web/live/agent_card_component.ex
defp card_state_class(_content_type, :approval_pending), do: "agent-card-blocked"
# This must be changed to a new class "agent-card-approval" with purple styling
# (currently reuses amber-keyed agent-card-blocked)
```

### status_dot_class — :approval_pending currently amber, needs purple
```elixir
# Source: lib/loomkin_web/live/agent_card_component.ex
defp status_dot_class(:approval_pending), do: "bg-amber-400 agent-dot-thinking"
# Must change to: "bg-violet-500 animate-pulse" to distinguish from permission (amber)
```

### Tools Registry — known_param_keys needs new atoms
```elixir
# Source: lib/loomkin/tools/registry.ex
# Add to @known_param_keys: :gate_id, :gate_context
# Add "request_approval" to appropriate tool list (peer_tools, since it needs team context)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual signal subscriptions | TeamBroadcaster aggregator | Phase 2 | All signals route through TeamBroadcaster; critical signals bypass batch window |
| Flat agent status | Typed state machine atoms with guards | Phase 5 | `:approval_pending` guard for `request_pause` already in place |
| Monolithic workspace_live | Extracted LiveComponents | Phase 1 | AgentCardComponent renders per-card; workspace_live handles signals |
| Permission-only intervention model | Permission + Approval as distinct mechanisms | Phase 5/6 boundary | Amber = permission (hook-triggered), Purple = approval (tool-triggered) |

**Deprecated/outdated:**
- `status_dot_class(:approval_pending)`: currently emits amber (`bg-amber-400`) — must be changed to violet/purple to satisfy the visual distinction requirement.
- `card_state_class(:approval_pending)`: currently maps to `agent-card-blocked` (amber CSS) — needs its own class `agent-card-approval` with purple border.

---

## Open Questions

1. **Approval panel on focused (expanded) card view**
   - What we know: The card has two render modes: grid view (compact) and focused view (full-screen, `@focused = true`).
   - What's unclear: Should the approval panel render in both modes? The CONTEXT.md only describes the grid card expansion.
   - Recommendation: Render in both modes. The focused view should show the approval panel prominently at the top of the card content area.

2. **Global timeout configuration location**
   - What we know: CONTEXT.md says "configurable globally (app config)". Elixir app config is in `config/config.exs`.
   - What's unclear: What config key to use; whether it belongs under `:loomkin` top-level or a nested key.
   - Recommendation: `config :loomkin, :approval_gate_timeout_ms, 300_000`. Read in `RequestApproval` as `Application.get_env(:loomkin, :approval_gate_timeout_ms, 300_000)`.

3. **Agent GenServer `:approval_pending` status**
   - What we know: The pre-wired guard `handle_cast(:request_pause, %{status: :approval_pending})` exists but Phase 6 uses a UI-only approach (signal-driven).
   - What's unclear: Whether the planner should have a task to call `set_status_and_broadcast(state, :approval_pending)` when the `ApprovalRequested` signal is received by... the agent itself?
   - Recommendation: Keep it UI-only for Phase 6 as described in Architecture Pattern 2 above. The guard stays as dead-but-harmless code. If needed in a future phase, re-evaluate.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built into Elixir/OTP) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin/tools/request_approval_test.exs test/loomkin/teams/agent_state_machine_test.exs --no-start` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTV-02 | RequestApproval tool blocks and returns approved result | unit | `mix test test/loomkin/tools/request_approval_test.exs::RequestApprovalTest.test_approves_and_returns -x` | ❌ Wave 0 |
| INTV-02 | RequestApproval tool returns timeout/denial after timeout_ms | unit | `mix test test/loomkin/tools/request_approval_test.exs::RequestApprovalTest.test_timeout -x` | ❌ Wave 0 |
| INTV-02 | ApprovalRequested signal is classified critical in TeamBroadcaster | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | ❌ Wave 0 |
| INTV-02 | :approval_pending status dot is violet, not amber | unit (component) | `mix test test/loomkin_web/live/agent_card_component_test.exs::approval_pending -x` | ✅ (existing test, needs assertion update) |
| INTV-02 | Approve/Deny/Approve w/ Context buttons render when card has pending_approval assign | unit (component) | `mix test test/loomkin_web/live/agent_card_component_test.exs::approval_panel -x` | ❌ Wave 0 |
| INTV-02 | workspace_live approve_card_agent routes response to blocking tool task | integration | `mix test test/loomkin_web/live/workspace_live_approval_test.exs -x` | ❌ Wave 0 |
| INTV-02 | Leader banner appears when agent role == :lead hits approval gate | integration | `mix test test/loomkin_web/live/workspace_live_approval_test.exs::leader_banner -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/tools/request_approval_test.exs test/loomkin_web/live/agent_card_component_test.exs --no-start`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin/tools/request_approval_test.exs` — covers blocking approval, response routing, and timeout behavior
- [ ] `test/loomkin/teams/team_broadcaster_test.exs` — verify critical_types includes approval signal types (file may or may not exist)
- [ ] `test/loomkin_web/live/workspace_live_approval_test.exs` — integration tests for LiveView event handlers and leader banner
- [ ] Update `test/loomkin_web/live/agent_card_component_test.exs` — update `:approval_pending` dot assertion (amber → violet) and add approval panel render tests

---

## Sources

### Primary (HIGH confidence)
- Direct codebase read: `lib/loomkin/tools/ask_user.ex` — canonical blocking tool pattern
- Direct codebase read: `lib/loomkin/teams/agent.ex` — GenServer state machine, `set_status_and_broadcast`, `force_pause`, `permission_response` patterns
- Direct codebase read: `lib/loomkin/teams/team_broadcaster.ex` — `@critical_types` MapSet, critical vs batchable classification
- Direct codebase read: `lib/loomkin_web/live/agent_card_component.ex` — `:approval_pending` pre-wiring, card UI structure, `card_state_class`, `status_dot_class`
- Direct codebase read: `lib/loomkin_web/live/agent_comms_component.ex` — `@type_config` structure, purple/violet color values already used
- Direct codebase read: `lib/loomkin/signals/agent.ex`, `lib/loomkin/signals/team.ex` — signal struct definition pattern
- Direct codebase read: `lib/loomkin/tools/registry.ex` — tool registration, `@known_param_keys`, tool list categories
- Direct codebase read: `test/loomkin/teams/agent_state_machine_test.exs` — test patterns for GenServer state
- Direct codebase read: `test/loomkin_web/live/agent_card_component_test.exs` — component test patterns
- Direct codebase read: `.planning/phases/06-approval-gates/06-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence)
- Elixir `Process.send_after/3` + `receive after` — OTP standard mechanism; well-understood

### Tertiary (LOW confidence)
- JS hook countdown timer approach — based on Phoenix LiveView hook patterns established in project (CommsFeedScroll); not verified against a specific doc

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all mechanisms exist and are proven
- Architecture: HIGH — all patterns traced directly to existing working code
- Pitfalls: HIGH — derived from actual code structure and signal delivery guarantees
- UI pattern: MEDIUM — Tailwind class suggestions based on existing palette; exact color values are Claude's discretion per CONTEXT.md

**Research date:** 2026-03-08
**Valid until:** 2026-04-08 (stable codebase; no external library churn expected)
