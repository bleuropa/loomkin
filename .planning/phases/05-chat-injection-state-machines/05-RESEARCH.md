# Phase 5: Chat Injection & State Machines - Research

**Researched:** 2026-03-07
**Domain:** Elixir GenServer state management, Phoenix LiveView UI patterns, broadcast messaging
**Confidence:** HIGH

## Summary

Phase 5 addresses two related concerns: (1) human broadcast messaging to an entire agent team, and (2) fixing the state clobbering bug where `pending_permission` can be overwritten by a pause request. The codebase is well-structured for both changes -- the Agent GenServer already has `set_status_and_broadcast/2` as a single status transition point, `pause_requested` as a separate flag from `status`, and `pending_permission` as a separate field. The ComposerComponent already has an "Entire Kin" option that sets `agent: "team"` but currently just clears `reply_target` to nil (falling through to the Architect pipeline).

The broadcast feature requires: a new `broadcast_mode` assign in workspace_live, a 4th branch in `handle_event("send_message", ...)` that iterates team agents and calls `Agent.send_message/2` on each, new comms event types (`:human_broadcast`, `:human_reply`), and a visual indicator in the composer. The state machine fix requires: guard clauses in `set_status_and_broadcast/2` and `handle_cast(:request_pause, ...)` to prevent dangerous transitions, a `pause_queued` flag for when pause is requested during `waiting_permission`, and distinct UI controls for the two states on the agent card.

**Primary recommendation:** Implement guard-based state transition protection first (it is the safety fix), then layer broadcast messaging on top. Use Elixir pattern matching on function heads for guards -- the natural Elixir idiom, not runtime conditional checks.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Messages delivered at each agent's next checkpoint (between tool calls / iterations) -- non-disruptive, agents finish current work first
- All agents receive the broadcast including paused and crashed ones -- paused agents see it when resumed, crashed agents see it if they recover
- Root team only -- broadcast does not cascade to sub-teams
- Context-dependent default: solo sessions default to Architect pipeline; team sessions default to broadcast
- Agent count badge near the broadcast indicator (e.g., "5 agents")
- Guards on key transitions -- keep the current flat-atom status approach but add guard clauses on dangerous transitions
- When pause is requested during pending_permission: queue the pause. After permission is resolved, agent automatically transitions to paused
- If permission is denied with a queued pause: agent still pauses (does not resume to handle denial)
- Dual indicator on agent card when both states active: permission-pending as primary status + small "pause queued" badge
- Pause and permission controls are different buttons entirely -- pause shows a pause icon button; permission shows approve/deny buttons with tool call details
- Resuming a paused agent requires providing guidance text -- mandatory, not optional
- Pre-wire `:approval_pending` as a recognized state with guards now (for Phase 6)
- Only key state transitions emit signals to comms feed (paused, permission requested, error)
- Last-transition hint on agent card: shows current state plus small "from: working" context
- Force-pause escape hatch: warns "This will cancel the pending permission" and requires confirmation

### Claude's Discretion
- Broadcast acknowledgment behavior (whether agents emit receipt events)
- Composer broadcast indicator visual design (reply bar pattern vs button mode)
- Mode switching UX (@ button picker vs keyboard shortcut)
- Force-pause confirmation UX design
- Which specific state transitions are "key" enough to emit signals
- Exact guard clause implementation (function heads vs explicit checks)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTV-01 | Human can broadcast a chat message to the entire team conversation (not just reply-to-agent) | Composer already has "Entire Kin" option; workspace_live needs 4th send_message branch; TeamBroadcaster critical signal path for delivery; new comms event types |
| INTV-04 | Typed state machine separates pause vs permission vs approval gate states to prevent clobbering | Agent GenServer has `set_status_and_broadcast/2` as single transition point; `pending_permission` is separate field from `status`; guard clauses on function heads; `pause_queued` flag |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix LiveView | existing | Real-time UI updates for broadcast indicator, state badges | Already the app's UI framework |
| Elixir GenServer | OTP 27 | Agent state management, guard clauses via pattern matching | Already the Agent's process model |
| Jido Signal Bus | existing | Broadcasting state transition signals to comms feed | Already wired via TeamBroadcaster |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Registry | OTP 27 | Looking up all agents in a team for broadcast delivery | Already used for agent lookup |
| Task.Supervisor | OTP 27 | Async broadcast delivery to avoid blocking LiveView | Already used for agent calls |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pattern-match guards | Explicit `cond`/`case` in single function | Pattern matching is idiomatic Elixir and lets the compiler check exhaustiveness |
| Iterating agents for broadcast | PubSub broadcast to team topic | Direct iteration gives delivery guarantees; PubSub is fire-and-forget |

## Architecture Patterns

### Recommended Project Structure
No new files needed. Changes go into existing modules:
```
lib/loomkin/teams/agent.ex                          # Guard clauses, pause_queued flag, approval_pending state
lib/loomkin_web/live/workspace_live.ex               # Broadcast send branch, broadcast_mode assign
lib/loomkin_web/live/composer_component.ex           # Broadcast indicator, agent count badge
lib/loomkin_web/live/agent_card_component.ex         # Dual state indicator, distinct pause/permission controls
lib/loomkin_web/live/agent_comms_component.ex        # New event types: human_broadcast, state transitions
```

### Pattern 1: Guard Clauses via Function Head Matching
**What:** Use multiple `handle_cast`/`handle_call` function heads with pattern matches on state fields to prevent dangerous transitions.
**When to use:** Every status transition that could clobber another state.
**Example:**
```elixir
# Block pause request when permission is pending -- queue it instead
def handle_cast(:request_pause, %{status: :waiting_permission} = state) do
  {:noreply, %{state | pause_queued: true}}
end

# Normal pause request when not in permission state
def handle_cast(:request_pause, state) do
  {:noreply, %{state | pause_requested: true}}
end
```

### Pattern 2: Coordinated State Transition After Permission Resolution
**What:** When permission is resolved and `pause_queued` is true, auto-transition to paused instead of resuming work.
**When to use:** In the `handle_cast({:permission_response, ...})` handler.
**Example:**
```elixir
# In permission_response handler, after processing:
if state.pause_queued do
  paused_state = %{messages: messages, iteration: nil, reason: :user_requested}
  state = %{state | pending_permission: nil, pause_queued: false, paused_state: paused_state}
  state = set_status_and_broadcast(state, :paused)
  {:noreply, state}
else
  # Normal permission resolution flow (existing code)
end
```

### Pattern 3: Broadcast Mode in Workspace
**What:** A `broadcast_mode` boolean assign that changes how "Entire Kin" option routes messages.
**When to use:** In workspace_live's `handle_info({:composer_event, "select_reply_target", %{"agent" => "team"}})`.
**Example:**
```elixir
# Instead of clearing reply_target to nil (Architect pipeline):
def handle_info({:composer_event, "select_reply_target", %{"agent" => "team"}}, socket) do
  {:noreply, assign(socket, reply_target: nil, broadcast_mode: true)}
end

# In send_message, check broadcast_mode before falling through to Architect:
nil when socket.assigns.broadcast_mode ->
  # Broadcast to all team agents
  ...
nil ->
  # Architect pipeline (existing)
  ...
```

### Pattern 4: Broadcast Delivery Via Manager.list_agents
**What:** Use existing `Manager.find_agent/2` or Registry lookup to get all agent PIDs, then call `Agent.send_message/2` on each.
**When to use:** In the broadcast send_message branch.
**Example:**
```elixir
# Get all agents for the root team
agents = Loomkin.Teams.Manager.list_agents(team_id)
Enum.each(agents, fn {name, pid} ->
  Task.Supervisor.start_child(Loomkin.Teams.TaskSupervisor, fn ->
    Agent.send_message(pid, "[Broadcast from Human]: #{text}")
  end)
end)
```

### Anti-Patterns to Avoid
- **Direct status assignment without guards:** Never do `%{state | status: :paused}` directly -- always go through `set_status_and_broadcast/2` which is the single transition point.
- **Blocking LiveView with synchronous broadcast:** Never call `Agent.send_message/2` synchronously from workspace_live for multiple agents -- use `Task.Supervisor.start_child` for each.
- **Conflating broadcast_mode with reply_target:** Keep `broadcast_mode` as a separate boolean -- don't try to encode "broadcast" as a special reply_target value, since `nil` reply_target already means "Architect pipeline."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Agent lookup for broadcast | Custom agent tracking | `Loomkin.Teams.Manager.list_agents/1` or Registry match | Registry already indexes agents by team_id |
| State transition validation | Custom state machine library | Pattern-matched function heads with guard clauses | Elixir's pattern matching IS the state machine; no library overhead needed |
| Broadcast delivery ordering | Custom ordering/queue system | `Task.Supervisor.start_child` for fire-and-forget delivery | Agents process messages at checkpoints anyway; ordering within a single broadcast batch is not critical |

**Key insight:** The existing Agent GenServer architecture with `status`, `pending_permission`, and `pause_requested` as separate fields already forms a state machine. The fix is adding guard clauses to the existing transition points, not replacing the architecture.

## Common Pitfalls

### Pitfall 1: Race Between Pause Request and Permission Resolution
**What goes wrong:** A pause cast arrives between when the loop emits `{:loop_pending, ...}` and when the GenServer processes it, causing the pause to overwrite permission state.
**Why it happens:** GenServer mailbox processes messages in order, but casts and info messages from different sources interleave unpredictably.
**How to avoid:** The guard clause on `handle_cast(:request_pause, ...)` checks `state.status` and `state.pending_permission` to decide whether to set `pause_requested` or `pause_queued`. Since both mutations happen inside the GenServer's sequential processing, there's no actual race -- the key is checking the right fields.
**Warning signs:** Agent card shows "paused" but the permission request disappears from the UI.

### Pitfall 2: Broadcast to Dead Agents
**What goes wrong:** An agent crashes between the time you list agents and the time you send the message.
**Why it happens:** PIDs from Registry can become stale.
**How to avoid:** Wrap each `Agent.send_message/2` call in a try/catch or use `Task.Supervisor.start_child` which handles failures gracefully. For crashed agents, the message is lost but that's acceptable per the CONTEXT.md decision (crashed agents see broadcasts if they recover -- recovery would need to re-check for pending broadcasts).
**Warning signs:** Error logs about sending to dead processes.

### Pitfall 3: Mandatory Guidance Breaking Quick Resume
**What goes wrong:** User clicks resume but there's no guidance text, and the UI doesn't prevent the action.
**Why it happens:** The current `resume_card_agent` handler calls `Agent.resume(pid)` with no options -- no guidance check.
**How to avoid:** The resume button should open the composer in steer mode (already exists) rather than directly calling resume. The existing `steer_card_agent` flow already requires text input. Remove the bare "resume" button for paused agents; only show "steer" which forces guidance.
**Warning signs:** Agent resumes with no direction, repeats previous behavior.

### Pitfall 4: Broadcast Mode Persisting After Send
**What goes wrong:** After sending a broadcast, `broadcast_mode` stays true and the next message also broadcasts.
**Why it happens:** Forgetting to reset `broadcast_mode` after send.
**How to avoid:** In the broadcast branch of `handle_event("send_message", ...)`, reset `broadcast_mode` to its context-dependent default (true for team sessions, false for solo).
**Warning signs:** Every message goes to all agents even when user selected a specific agent.

### Pitfall 5: Force-Pause Losing Permission Context
**What goes wrong:** Force-pause cancels the pending permission, but the denial context is not preserved for when the agent eventually resumes.
**Why it happens:** `pending_permission` is set to nil without saving the context.
**How to avoid:** On force-pause, save the cancelled permission info in `paused_state` metadata so the resume guidance can reference what was cancelled.
**Warning signs:** Agent resumes after force-pause with no memory of what it was trying to do.

## Code Examples

### Guard Clause: Prevent Pause Clobbering Permission
```elixir
# In agent.ex -- new function head BEFORE the existing handle_cast(:request_pause, ...)
def handle_cast(:request_pause, %{status: :waiting_permission} = state) do
  # Queue the pause -- it will execute after permission is resolved
  broadcast_team(state, {:agent_pause_queued, state.name})
  {:noreply, %{state | pause_queued: true}}
end

def handle_cast(:request_pause, state) do
  {:noreply, %{state | pause_requested: true}}
end
```

### Permission Resolution with Queued Pause
```elixir
# In agent.ex handle_cast({:permission_response, ...}), after processing tool result:
def handle_cast({:permission_response, action, tool_name, tool_path}, state) do
  case state.pending_permission do
    nil -> {:noreply, state}
    pending_info ->
      # ... existing permission processing ...

      if state.pause_queued do
        # Permission resolved; now honor the queued pause
        denial_context = if action not in ["allow_once", "allow_always"],
          do: %{denied_tool: tool_name, denied_path: tool_path}

        paused_state = %{
          messages: state.messages,
          iteration: nil,
          reason: :user_requested,
          cancelled_permission: denial_context
        }

        state = %{state |
          pending_permission: nil,
          pause_queued: false,
          paused_state: paused_state
        }
        state = set_status_and_broadcast(state, :paused)
        {:noreply, state}
      else
        # ... existing resume-after-permission flow ...
      end
  end
end
```

### Broadcast Send Branch in Workspace
```elixir
# In workspace_live.ex handle_event("send_message", ...) -- new 4th branch:
def handle_event("send_message", %{"text" => text}, socket) when text != "" do
  trimmed = String.trim(text)

  case {socket.assigns.reply_target, socket.assigns.broadcast_mode} do
    {%{mode: :steer}, _} ->
      # Existing steer branch...

    {%{agent: agent_name, team_id: team_id}, _} ->
      # Existing direct reply branch...

    {nil, true} ->
      # BROADCAST: send to all team agents
      team_id = socket.assigns.team_id
      agents = Loomkin.Teams.Manager.list_agents(team_id)

      Enum.each(agents, fn {_name, pid} ->
        Task.Supervisor.start_child(Loomkin.Teams.TaskSupervisor, fn ->
          Loomkin.Teams.Agent.send_message(pid, "[Broadcast from Human]: #{trimmed}")
        end)
      end)

      broadcast_event = %{
        id: Ecto.UUID.generate(),
        type: :human_broadcast,
        agent: "You",
        content: trimmed,
        timestamp: DateTime.utc_now(),
        expanded: false,
        metadata: %{from: "You", to: "All Agents", agent_count: length(agents)}
      }

      {:noreply,
       socket
       |> push_activity_event(broadcast_event)
       |> assign(input_text: "", last_user_message: %{text: trimmed, to: "All Agents"})
       |> push_event("clear-input", %{})}

    {nil, _} ->
      # Existing Architect pipeline branch...
  end
end
```

### New Comms Event Types
```elixir
# In agent_comms_component.ex @type_config, add:
human_broadcast: %{
  icon: "📢",
  accent_border: "rgba(251, 191, 36, 0.35)",
  accent_text: "#fcd34d",
  accent_bg: "rgba(251, 191, 36, 0.10)"
},
human_reply: %{
  icon: "💬",
  accent_border: "rgba(52, 211, 153, 0.30)",
  accent_text: "#6ee7b7",
  accent_bg: "rgba(52, 211, 153, 0.08)"
},
agent_paused: %{
  icon: "⏸",
  accent_border: "rgba(96, 165, 250, 0.30)",
  accent_text: "#93bbfd",
  accent_bg: "rgba(96, 165, 250, 0.08)"
},
permission_requested: %{
  icon: "🔒",
  accent_border: "rgba(251, 146, 60, 0.35)",
  accent_text: "#fdba74",
  accent_bg: "rgba(251, 146, 60, 0.10)"
}
```

### Agent Card Dual State Indicator
```elixir
# In agent_card_component.ex, add after crash_count badge:
<span
  :if={@card[:pause_queued]}
  class="ml-1 px-1 py-0.5 text-[8px] font-mono bg-blue-900/50 text-blue-300 rounded animate-pulse"
>
  pause queued
</span>
```

### Valid State Transitions (for guard reference)
```
:idle        -> :working (send_message, resume, assign_task)
:working     -> :idle (loop_ok, cancel)
:working     -> :paused (loop_paused via pause_requested)
:working     -> :waiting_permission (loop_pending)
:working     -> :error (loop failure)
:paused      -> :working (resume with guidance)
:paused      -> :idle (cancel)
:waiting_permission -> :working (permission approved, no pause queued)
:waiting_permission -> :paused (permission resolved + pause_queued)
:waiting_permission -> :idle (cancel, force-pause)
:approval_pending   -> :working (approval granted) [Phase 6 pre-wire]
:approval_pending   -> :idle (approval denied) [Phase 6 pre-wire]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `pending_permission` overwrites status | Guard clauses prevent clobbering | This phase | Fixes the identified bug in STATE.md |
| "Entire Kin" clears reply_target (Architect pipeline) | "Entire Kin" sets broadcast_mode for team sessions | This phase | Enables true team-wide messaging |
| Single resume button | Steer-only resume (mandatory guidance) | This phase | Forces intentional re-direction |

**Deprecated/outdated:**
- Bare `resume_card_agent` button without guidance: replaced by steer-only flow requiring text input

## Open Questions

1. **Broadcast delivery to paused agents**
   - What we know: CONTEXT.md says "paused agents see it when resumed"
   - What's unclear: Should the broadcast message be injected into `paused_state.messages` immediately, or should there be a separate `pending_broadcasts` queue that gets drained on resume?
   - Recommendation: Inject into `paused_state.messages` directly since the agent's message list is preserved in `paused_state` and will be used when resumed. This is simpler and follows the existing pattern.

2. **Manager.list_agents availability**
   - What we know: `Manager.find_agent/2` exists for single agent lookup
   - What's unclear: Whether `Manager.list_agents/1` exists or needs to be created
   - Recommendation: Check at implementation time. If it doesn't exist, a Registry match on team_id pattern is straightforward.

3. **Broadcast acknowledgment**
   - What we know: Claude's discretion per CONTEXT.md
   - Recommendation: Skip agent acknowledgment events. Broadcasts are human-to-team; the comms feed shows the broadcast event itself. Agent ACKs would be noise. If an agent's behavior changes due to the broadcast, that will show in its normal status/activity signals.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin/teams/agent_test.exs test/loomkin/teams/agent_checkpoint_test.exs --max-failures 3` |
| Full suite command | `mix test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTV-01a | Broadcast message delivered to all team agents | unit | `mix test test/loomkin/teams/agent_broadcast_test.exs -x` | No -- Wave 0 |
| INTV-01b | Broadcast appears in comms feed as human operator | integration | `mix test test/loomkin_web/live/workspace_broadcast_test.exs -x` | No -- Wave 0 |
| INTV-01c | Composer shows broadcast mode indicator with agent count | unit | `mix test test/loomkin_web/live/composer_component_test.exs -x` | Yes (exists, needs new tests) |
| INTV-04a | Pause during pending_permission queues the pause | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs -x` | No -- Wave 0 |
| INTV-04b | Permission resolution with queued pause auto-pauses | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs -x` | No -- Wave 0 |
| INTV-04c | Resume requires guidance text (mandatory) | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs -x` | No -- Wave 0 |
| INTV-04d | Force-pause cancels permission with confirmation | integration | `mix test test/loomkin_web/live/workspace_state_machine_test.exs -x` | No -- Wave 0 |
| INTV-04e | Agent card shows distinct pause vs permission controls | unit | `mix test test/loomkin_web/live/agent_card_component_test.exs -x` | No -- Wave 0 |
| INTV-04f | Approval_pending pre-wired as recognized state | unit | `mix test test/loomkin/teams/agent_state_machine_test.exs -x` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/teams/agent_state_machine_test.exs test/loomkin/teams/agent_broadcast_test.exs --max-failures 3`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin/teams/agent_state_machine_test.exs` -- covers INTV-04a, INTV-04b, INTV-04c, INTV-04f
- [ ] `test/loomkin/teams/agent_broadcast_test.exs` -- covers INTV-01a
- [ ] `test/loomkin_web/live/workspace_broadcast_test.exs` -- covers INTV-01b
- [ ] `test/loomkin_web/live/workspace_state_machine_test.exs` -- covers INTV-04d
- [ ] `test/loomkin_web/live/agent_card_component_test.exs` -- covers INTV-04e (card does not have test file yet)

## Sources

### Primary (HIGH confidence)
- Direct code inspection of `lib/loomkin/teams/agent.ex` -- status field, pending_permission field, pause_requested flag, set_status_and_broadcast/2, handle_cast(:request_pause), handle_cast({:permission_response, ...}), handle_call({:resume, ...}), handle_call({:checkpoint, ...})
- Direct code inspection of `lib/loomkin_web/live/workspace_live.ex` -- handle_event("send_message") 3-branch structure, composer_event handlers, reply_target management, pause/resume/steer agent handlers
- Direct code inspection of `lib/loomkin_web/live/composer_component.ex` -- "Entire Kin" option, agent picker, event forwarding pattern
- Direct code inspection of `lib/loomkin_web/live/agent_card_component.ex` -- status_dot_class, action buttons for pause/resume/steer, card_state_class
- Direct code inspection of `lib/loomkin_web/live/agent_comms_component.ex` -- @type_config map, comms_row rendering
- `.planning/phases/05-chat-injection-state-machines/05-CONTEXT.md` -- all locked decisions
- `.planning/STATE.md` -- "pending_permission can be overwritten -- must be fixed in Phase 5"
- `test/loomkin/teams/agent_checkpoint_test.exs` -- existing pause/resume test patterns

### Secondary (MEDIUM confidence)
- Elixir GenServer pattern matching for state guards -- standard OTP pattern, well-documented

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already in use, no new dependencies
- Architecture: HIGH - direct code inspection confirms all integration points and existing patterns
- Pitfalls: HIGH - identified from actual code paths (race conditions in GenServer, stale PIDs, broadcast_mode persistence)

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- internal codebase, no external API changes)
