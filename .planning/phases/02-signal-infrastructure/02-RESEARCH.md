# Phase 2: Signal Infrastructure - Research

**Researched:** 2026-03-07
**Domain:** Elixir GenServer design, Jido Signal Bus integration, message batching/debounce
**Confidence:** HIGH

## Summary

Phase 2 builds a TeamBroadcaster GenServer that interposes between the Jido Signal Bus and LiveView processes. Currently, workspace_live subscribes to 8+ glob patterns on the signal bus directly and receives every signal for every team, filtering at dispatch time via `signal_for_workspace?/2`. With 10 concurrent streaming agents, each producing stream deltas, tool events, and status updates, the LiveView message queue becomes saturated.

TeamBroadcaster solves this by subscribing to the bus once, classifying signals as critical (instant forward) vs. batchable (50ms window), and delivering grouped summaries to LiveView subscribers via `send/2`. A Topics module centralizes all topic string generation for both Jido Signal Bus paths and Phoenix PubSub topics, eliminating raw string interpolation across the codebase.

The critical gap is subscription cleanup: `Signals.subscribe/1` returns `{:ok, subscription_id}` but no caller in the codebase stores or uses these IDs. The `Loomkin.Signals` module lacks an `unsubscribe/1` function entirely. Both TeamBroadcaster and Agent GenServers need to track subscription IDs and call `Jido.Signal.Bus.unsubscribe/2` in their `terminate/2` callbacks.

**Primary recommendation:** Build TeamBroadcaster as a GenServer started per-session under a DynamicSupervisor, using `Process.monitor/1` for subscriber lifecycle tracking, `:timer.send_interval` or `Process.send_after/3` for the 50ms batch window, and `:telemetry.execute/3` for instrumentation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Priority bypass for critical signals: crashes, permission requests, and ask-user signals skip debouncing and forward instantly
- All other signals (streaming deltas, tool progress, activity updates) batched in 50ms windows
- Batched summaries grouped by signal type so LiveView handles each group separately
- Fixed 50ms debounce window -- no runtime configurability needed
- One TeamBroadcaster GenServer per session (matches workspace_live one-LiveView-per-session pattern)
- TeamBroadcaster wraps Jido Signal Bus signals only -- Phoenix PubSub session events remain as-is
- workspace_live subscribes exclusively via TeamBroadcaster -- no direct Jido Signal Bus subscriptions from LiveView
- TeamBroadcaster delivers to subscribers via direct process messages (send/2), matching existing Jido Signal Bus delivery pattern
- Emit :telemetry events for batch size and queue depth -- no UI work, just instrument for future observability
- Topics module covers LiveView-facing topics only: agent.**, team.**, context.**, decision.**, channel.** and per-team topic generation
- Signal type definitions stay in signals/*.ex where they belong
- Both Jido Signal Bus paths AND Phoenix PubSub topic strings in one Topics module
- Regular functions (e.g., Topics.team_activity(team_id), Topics.agent_status(agent_id)) -- no macros or compile-time constants
- TeamBroadcaster uses Process.monitor on each subscriber -- auto-cleans on {:DOWN, ...} when LiveView dies
- Clean break: old direct Jido subscriptions removed from workspace_live entirely in this phase
- Agent-level GenServers (Loomkin.Teams.Agent) also get unsubscribe cleanup in terminate/2

### Claude's Discretion
- Internal TeamBroadcaster state structure and timer management
- How to group/classify signal types for priority bypass vs batching
- Exact Jido Signal Bus unsubscribe API usage
- Test strategy for verifying message queue depth under load
- Whether TeamBroadcaster should be supervised per-session or under a dynamic supervisor

### Deferred Ideas (OUT OF SCOPE)
None
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOUN-02 | TeamBroadcaster aggregator GenServer sits between Signal Bus and LiveView to batch and throttle events, preventing mailbox overload | TeamBroadcaster GenServer design, 50ms batch window, priority bypass for critical signals, telemetry instrumentation |
| FOUN-03 | Signal Bus subscriptions cleaned up with unsubscribe in terminate/2 and Topics module for topic string management | Jido.Signal.Bus.unsubscribe/2 API, subscription ID tracking, Topics module design, Process.monitor for subscriber cleanup |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GenServer (Elixir stdlib) | OTP 27+ | TeamBroadcaster process | Standard OTP pattern for stateful processes with message handling |
| Process.monitor/1 | OTP 27+ | Subscriber lifecycle tracking | Built-in; receives {:DOWN, ref, :process, pid, reason} when monitored process dies |
| :telemetry | ~> 1.x | Batch size and queue depth metrics | Already used in Loomkin.Telemetry; standard BEAM instrumentation |
| Jido.Signal.Bus | (dep) | Signal subscribe/unsubscribe/publish | Already in supervision tree as Loomkin.SignalBus |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DynamicSupervisor | OTP 27+ | Per-session TeamBroadcaster supervision | Starting/stopping broadcasters with session lifecycle |
| Process.send_after/3 | OTP 27+ | 50ms batch flush timer | Each batch window reset |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Process.send_after for timer | :timer.send_interval | send_after is more flexible -- timer resets on each batch, avoids sending flushes when idle |
| DynamicSupervisor | Start under Loomkin.Teams.Supervisor | DynamicSupervisor is cleaner for per-session lifecycle; Teams.Supervisor is for agents |
| send/2 delivery | Phoenix.PubSub | send/2 matches existing Jido delivery pattern; PubSub adds unnecessary indirection |

## Architecture Patterns

### Recommended Project Structure
```
lib/loomkin/teams/
  team_broadcaster.ex    # GenServer: subscribe to bus, batch, forward
  topics.ex              # Topic string generation for both bus paths and PubSub
lib/loomkin/signals.ex   # Add unsubscribe/1 wrapper
```

### Pattern 1: TeamBroadcaster GenServer State
**What:** A GenServer that holds signal subscriptions, subscriber PIDs with monitors, and a batch buffer
**When to use:** Per-session, started when workspace_live mounts

```elixir
defmodule Loomkin.Teams.TeamBroadcaster do
  use GenServer

  defstruct [
    :team_ids,           # MapSet of subscribed team IDs
    :flush_ref,          # Current Process.send_after timer ref (nil when idle)
    subscription_ids: [],  # Jido Signal Bus subscription IDs for cleanup
    subscribers: %{},    # %{pid => monitor_ref}
    buffer: %{           # Batched signals grouped by category
      streaming: [],
      tools: [],
      activity: [],
      status: []
    }
  ]

  @flush_interval_ms 50

  # Public API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def subscribe(broadcaster, pid), do: GenServer.call(broadcaster, {:subscribe, pid})
  def add_team(broadcaster, team_id), do: GenServer.call(broadcaster, {:add_team, team_id})

  # Init: subscribe to Jido Signal Bus
  def init(opts) do
    team_ids = MapSet.new(opts[:team_ids] || [])
    state = %__MODULE__{team_ids: team_ids}
    state = subscribe_to_bus(state)
    {:ok, state}
  end

  # Critical signals bypass batching
  def handle_info({:signal, %Jido.Signal{type: "team.permission.request"} = sig}, state) do
    if signal_for_teams?(sig, state.team_ids) do
      broadcast_immediate(state.subscribers, {:team_broadcast, %{critical: [sig]}})
    end
    {:noreply, state}
  end

  # Batchable signals accumulate in buffer
  def handle_info({:signal, %Jido.Signal{} = sig}, state) do
    if signal_for_teams?(sig, state.team_ids) do
      category = classify_signal(sig)
      state = buffer_signal(state, category, sig)
      state = ensure_flush_timer(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Timer fires: flush buffer to all subscribers
  def handle_info(:flush, state) do
    broadcast_batch(state.subscribers, state.buffer)
    {:noreply, %{state | buffer: empty_buffer(), flush_ref: nil}}
  end

  # Subscriber died
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_subscriber(state, pid)}
  end

  def terminate(_reason, state) do
    # Unsubscribe from Jido Signal Bus
    for sub_id <- state.subscription_ids do
      Loomkin.Signals.unsubscribe(sub_id)
    end
    :ok
  end
end
```

### Pattern 2: Topics Module
**What:** Centralized topic string generation for all bus paths and PubSub topics
**When to use:** Everywhere that currently uses raw string interpolation for topics

```elixir
defmodule Loomkin.Teams.Topics do
  @moduledoc "Generates topic strings for Jido Signal Bus and Phoenix PubSub."

  # Jido Signal Bus glob paths
  def agent_all, do: "agent.**"
  def agent_stream(agent_id), do: "agent.stream.#{agent_id}"
  def team_all, do: "team.**"
  def context_all, do: "context.**"
  def decision_all, do: "decision.**"
  def channel_all, do: "channel.**"
  def collaboration_all, do: "collaboration.**"
  def system_all, do: "system.**"
  def session_all, do: "session.**"
  def collaboration_vote_all, do: "collaboration.vote.*"

  # Phoenix PubSub topics
  def team_pubsub(team_id), do: "team:#{team_id}"

  # All global bus subscription paths
  def global_bus_paths do
    [agent_all(), team_all(), context_all(), decision_all(),
     channel_all(), collaboration_all(), system_all()]
  end
end
```

### Pattern 3: Signals.unsubscribe Addition
**What:** Add unsubscribe wrapper to the existing Loomkin.Signals module
**When to use:** In terminate/2 callbacks for any process that subscribed to the bus

```elixir
# Addition to Loomkin.Signals
def unsubscribe(subscription_id) do
  Bus.unsubscribe(@bus, subscription_id)
end
```

### Anti-Patterns to Avoid
- **Subscribing without tracking IDs:** Every `Signals.subscribe` call returns `{:ok, subscription_id}` -- this MUST be stored for cleanup. Currently no caller does this.
- **send_after without cancel:** When resetting the flush timer, always `Process.cancel_timer/1` the old ref before setting a new one. Otherwise a late flush races with the next batch.
- **Global subscription from LiveView:** workspace_live currently subscribes to `agent.**`, `team.**`, etc. globally -- every signal hits every LiveView. TeamBroadcaster should filter by team_id before forwarding.
- **Blocking in handle_info:** TeamBroadcaster signal classification and buffering must be non-blocking. No GenServer.call inside handle_info.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timer management | Custom timer process | Process.send_after/3 + Process.cancel_timer/1 | Built-in, no extra process, handles edge cases |
| Process monitoring | Manual PID tracking with periodic health checks | Process.monitor/1 | {:DOWN, ...} messages are guaranteed, no polling needed |
| Telemetry | Custom metrics collection | :telemetry.execute/3 | Already used in Loomkin.Telemetry; standard pattern |
| Subscription tracking | Manual PID-to-subscription map | Store subscription_ids from Bus.subscribe return | Bus already provides IDs; just store them |

**Key insight:** The Jido Signal Bus already handles all the hard parts (glob matching, PID delivery). TeamBroadcaster only needs to batch/throttle the output -- it does not need to re-implement routing.

## Common Pitfalls

### Pitfall 1: Timer Accumulation
**What goes wrong:** If `ensure_flush_timer` doesn't check whether a timer is already pending, multiple timers accumulate and fire in quick succession, defeating the batching purpose.
**Why it happens:** Each incoming signal calls ensure_flush_timer. Without the nil-check, each creates a new timer.
**How to avoid:** Only set timer when `state.flush_ref == nil`. Store the ref; clear it to nil after flush.
**Warning signs:** Batch sizes of 1-2 signals despite high throughput.

### Pitfall 2: Subscription ID Leak
**What goes wrong:** If TeamBroadcaster subscribes to bus paths but doesn't store the subscription IDs, `terminate/2` cannot unsubscribe, and the bus accumulates dead subscriptions.
**Why it happens:** `Loomkin.Signals.subscribe/1` returns `{:ok, subscription_id}` but the current codebase discards it everywhere.
**How to avoid:** Capture every `{:ok, sub_id}` return and accumulate in `state.subscription_ids`.
**Warning signs:** Bus subscription count grows monotonically across session restarts.

### Pitfall 3: Race Between add_team and Flush
**What goes wrong:** If `add_team/2` adds a new team_id but signals for that team were already buffered (before the team was added), those signals are lost.
**Why it happens:** Team subscription is dynamic (child teams spawn mid-session).
**How to avoid:** When adding a team, also replay recent signals for that team from the bus journal.
**Warning signs:** Newly joined sub-teams show no activity until their next signal.

### Pitfall 4: LiveView Reconnect Double-Subscribe
**What goes wrong:** If workspace_live reconnects (e.g., websocket drop), it may create a second TeamBroadcaster or subscribe twice.
**Why it happens:** LiveView mount runs again on reconnect.
**How to avoid:** Use a Registry or session-keyed lookup to find existing broadcaster. Make subscribe idempotent (check if PID already in subscribers map).
**Warning signs:** Duplicate messages in LiveView after reconnection.

### Pitfall 5: Forgetting Agent-Level Cleanup
**What goes wrong:** FOUN-03 requires Agent GenServer terminate/2 to unsubscribe from signals, but the current Agent module (agent.ex) doesn't have subscription cleanup.
**Why it happens:** Agent subscribes to signals in handle_info clauses but never stores subscription IDs.
**How to avoid:** Audit Agent's init/handle_info for subscribe calls, store IDs in state, unsubscribe in terminate/2.
**Warning signs:** Signal bus subscription count grows as agents are spawned and terminated.

## Code Examples

### Current workspace_live Signal Subscription (to be replaced)
```elixir
# lib/loomkin_web/live/workspace_live.ex lines 2700-2713
# This entire block gets replaced by TeamBroadcaster subscription
defp subscribe_global_signals(socket) do
  if socket.assigns[:global_signals_subscribed] do
    socket
  else
    Loomkin.Signals.subscribe("agent.**")
    Loomkin.Signals.subscribe("team.**")
    Loomkin.Signals.subscribe("context.**")
    Loomkin.Signals.subscribe("decision.**")
    Loomkin.Signals.subscribe("channel.**")
    Loomkin.Signals.subscribe("collaboration.**")
    Loomkin.Signals.subscribe("system.**")
    assign(socket, global_signals_subscribed: true)
  end
end
```

### Jido Signal Bus Unsubscribe API
```elixir
# From deps/jido_signal/lib/jido_signal/bus.ex line 366-371
# subscribe returns {:ok, subscription_id}
# unsubscribe takes the bus name and subscription_id
@spec unsubscribe(server(), subscription_id(), Keyword.t()) :: :ok | {:error, term()}
def unsubscribe(bus, subscription_id, opts \\ [])
```

### Signal Delivery Format (what TeamBroadcaster receives)
```elixir
# Signals arrive as {:signal, %Jido.Signal{}} messages
# See agent.ex line 824:
def handle_info({:signal, %Jido.Signal{} = sig}, state)
```

### workspace_live Signal Filter (logic to move into TeamBroadcaster)
```elixir
# lib/loomkin_web/live/workspace_live.ex lines 2680-2688
defp signal_for_workspace?(sig, socket) do
  signal_team_id =
    get_in(sig.data, [:team_id]) ||
      get_in(sig, [Access.key(:extensions, %{}), "loomkin", "team_id"])
  subscribed_teams = socket.assigns[:subscribed_teams] || MapSet.new()
  signal_team_id == nil or MapSet.member?(subscribed_teams, signal_team_id)
end
```

### Signal Classification for Priority Bypass
```elixir
# Critical (instant forward):
#   "team.permission.request"
#   "team.ask_user.question"
#   "team.ask_user.answered"
#   "agent.error"
#   "agent.escalation"
#   "team.dissolved"

# Batchable:
#   "agent.stream.start" / "agent.stream.delta" / "agent.stream.end"
#   "agent.tool.executing" / "agent.tool.complete"
#   "agent.usage"
#   "agent.status"
#   "agent.role.changed"
#   "agent.queue.updated"
#   "team.task.assigned" / "team.task.completed" / "team.task.started"
#   "context.update" / "context.offloaded" / "context.keeper.created"
#   "decision.*"
#   "collaboration.peer.message" / "collaboration.vote.*"
#   "channel.*"
```

### Telemetry Emission Pattern
```elixir
# Match existing Loomkin.Telemetry patterns
:telemetry.execute(
  [:loomkin, :team_broadcaster, :flush],
  %{batch_size: length(all_signals), queue_depth: map_size(state.subscribers)},
  %{team_ids: MapSet.to_list(state.team_ids)}
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| LiveView subscribes directly to all bus paths | TeamBroadcaster intermediary (this phase) | Phase 2 | Prevents mailbox overload at 10+ agents |
| Raw topic strings sprinkled in code | Topics module centralizes all strings | Phase 2 | Prevents drift, enables refactoring |
| No unsubscribe on process death | Track subscription IDs + terminate cleanup | Phase 2 | Prevents dead subscription accumulation |

**Current workspace_live signal handling:**
- Lines 2700-2713: subscribes to 7 glob bus paths globally
- Line 2726: subscribes to Phoenix PubSub `"team:#{team_id}"` per team
- Lines 802-900+: 20+ handle_info clauses convert Jido.Signal to internal tuples
- Line 2680-2688: `signal_for_workspace?/2` filters by team_id at dispatch time

## Open Questions

1. **TeamBroadcaster supervisor placement**
   - What we know: Loomkin.Application has a DynamicSupervisor (SessionSupervisor) for sessions and Loomkin.Teams.Supervisor for agents
   - What's unclear: Should TeamBroadcaster live under SessionSupervisor (session lifecycle) or a new DynamicSupervisor?
   - Recommendation: Add a new `Loomkin.Teams.BroadcasterSupervisor` (DynamicSupervisor) under Loomkin.Application, since broadcaster lifecycle is tied to session but logically belongs in the teams domain

2. **Agent.ex subscription tracking**
   - What we know: Agent handles 20+ signal types in handle_info but the subscribe calls happen elsewhere (in init or manager)
   - What's unclear: Exactly which subscribe calls the Agent GenServer owns vs. which are owned by workspace_live
   - Recommendation: Audit agent.ex init to find its own subscribe calls; those need ID tracking and terminate cleanup

3. **Batch message format for stream compatibility**
   - What we know: workspace_live uses `stream/3` for comms feed; current handle_info clauses convert signals to internal tuples
   - What's unclear: Whether batched delivery requires workspace_live to iterate and apply each signal individually, or if a bulk update is possible
   - Recommendation: TeamBroadcaster delivers `{:team_broadcast, %{streaming: [...], tools: [...], ...}}` and workspace_live has a single handle_info clause that iterates and applies updates

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir stdlib) |
| Config file | test/test_helper.exs |
| Quick run command | `mix test test/loomkin/teams/team_broadcaster_test.exs --max-failures 3` |
| Full suite command | `mix test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUN-02a | TeamBroadcaster batches signals in 50ms windows | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | No -- Wave 0 |
| FOUN-02b | Critical signals bypass batching (instant forward) | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | No -- Wave 0 |
| FOUN-02c | workspace_live receives batched summaries not raw signals | integration | `mix test test/loomkin_web/live/workspace_live_broadcaster_test.exs -x` | No -- Wave 0 |
| FOUN-02d | Message queue under 50 with 10 concurrent agents | smoke | `mix test test/loomkin/teams/team_broadcaster_load_test.exs --include load -x` | No -- Wave 0 |
| FOUN-03a | Topics module generates all bus paths and PubSub topics | unit | `mix test test/loomkin/teams/topics_test.exs -x` | No -- Wave 0 |
| FOUN-03b | TeamBroadcaster unsubscribes from bus in terminate/2 | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | No -- Wave 0 |
| FOUN-03c | Agent GenServer unsubscribes in terminate/2 | unit | `mix test test/loomkin/teams/agent_unsubscribe_test.exs -x` | No -- Wave 0 |
| FOUN-03d | Dead subscriber cleanup via Process.monitor | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin/teams/team_broadcaster_test.exs test/loomkin/teams/topics_test.exs --max-failures 3`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin/teams/team_broadcaster_test.exs` -- covers FOUN-02a, FOUN-02b, FOUN-03b, FOUN-03d
- [ ] `test/loomkin/teams/topics_test.exs` -- covers FOUN-03a
- [ ] `test/loomkin/teams/team_broadcaster_load_test.exs` -- covers FOUN-02d (tagged @tag :load)
- [ ] No framework install needed -- ExUnit is already configured

## Sources

### Primary (HIGH confidence)
- `/Users/vinnymac/Sites/vinnymac/loomkin/deps/jido_signal/lib/jido_signal/bus.ex` -- subscribe/unsubscribe API signatures and behavior
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals.ex` -- current subscribe wrapper (no unsubscribe)
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/live/workspace_live.ex` -- current signal subscription and handling patterns (lines 100-106, 168-192, 769-900, 2680-2743, 3880-3910)
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/agent.ex` -- agent signal handling patterns (lines 822-980)
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/signals/agent.ex` and `team.ex` -- signal type definitions
- `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/application.ex` -- supervision tree structure

### Secondary (MEDIUM confidence)
- Pattern recommendations for GenServer batching based on standard OTP patterns (Process.send_after timer reset pattern)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all stdlib OTP, no new dependencies needed
- Architecture: HIGH -- direct analysis of existing code patterns; clear path from current to target
- Pitfalls: HIGH -- identified from concrete code analysis (subscription ID discarding, timer accumulation)

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable OTP patterns, project-specific analysis)
