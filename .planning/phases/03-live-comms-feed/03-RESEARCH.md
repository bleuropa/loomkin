# Phase 3: Live Comms Feed - Research

**Researched:** 2026-03-07
**Domain:** Phoenix LiveView real-time feeds, stream management, dynamic subscriptions
**Confidence:** HIGH

## Summary

Phase 3 wires agent-to-agent peer messages into the comms feed and ensures dynamically spawned sub-team agents auto-insert into the UI. The existing infrastructure is remarkably complete: `stream(:comms_events, [])` is already initialized, `stream_insert/3` is used throughout workspace_live, `subscribe_to_team/2` handles child team subscription including synthesized "joined" events, and `TeamBroadcaster` already pre-filters signals by team_id. The primary gap is that `collaboration.peer.message` signals (the Jido Signal type used by `Comms.send_to/3` and the `PeerMessage` tool) are not currently handled in workspace_live -- they fall through to the catch-all `handle_info(%Jido.Signal{type: _type}, socket)` at line 998 and are silently dropped.

The secondary work involves: (1) adding a `peer_message` event type to the comms feed type_config, (2) adding team badge indicators to distinguish sub-team origin, (3) implementing auto-scroll behavior with a "N new messages" indicator, (4) stream cap management to limit DOM size, and (5) card insertion/removal animations for dynamically spawned agents. All of this builds on patterns already established in workspace_live.

**Primary recommendation:** Add a `handle_info(%Jido.Signal{type: "collaboration.peer.message"})` clause that converts the signal into a comms event with `:peer_message` type, add `:peer_message` to `@comms_event_types`, and classify it as critical in TeamBroadcaster for sub-1-second delivery. Team badges and stream management are layered on afterward.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Flat mixed feed — all messages from root + sub-teams interleaved chronologically in one stream
- Sub-team messages get a subtle team badge/label to show origin team
- Auto-subscribe to sub-team signals when ChildTeamCreated signal arrives (workspace_live already does this pattern)
- Peer messages are critical signals — under 1 second from emission to feed appearance (TeamBroadcaster already bypasses batching for critical types)
- New agent cards fade in with brief glow/pulse highlight (1-2 seconds) at the end of the grid
- Cards appended at end — existing cards don't move, no layout shift
- Sub-team agent cards get a subtle team badge matching the comms feed badge style
- Terminated agents show dimmed/grayed "terminated" state for 2-3 seconds, then fade out
- All 15+ event types visible by default — full mission control visibility
- No filtering controls in this phase
- Auto-scroll when user is at bottom; hold position with "N new messages" indicator when scrolled up
- Feed capped at ~500 events via stream management — older events removed from DOM
- Independent per-agent colors via existing AgentColors phash2 — team identity shown via badges, not colors
- Same agent color used identically in card and comms feed

### Claude's Discretion
- Team badge visual design (pill, dot, tag — whatever communicates team origin clearly without clutter)
- Team badge depth indicator design (optional, if it helps distinguish root vs child vs grandchild)
- Auto-scroll detection mechanism (scroll position tracking approach)
- Stream cap implementation (LiveView stream limit vs manual pruning)
- Card fade/glow animation implementation (CSS transitions vs LiveView hooks)
- Card removal animation timing and approach

### Deferred Ideas (OUT OF SCOPE)
- Feed filtering controls (by event type, by team) — future phase
- Message threading / conversation grouping — future phase
- Feed search — future phase
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VISB-01 | Agent-to-agent messages visible in real-time comms feed for dynamically spawned sub-teams (bus subscription wired for dynamic team join) | Signal handler for `collaboration.peer.message`, TeamBroadcaster critical classification, subscribe_to_team already handles dynamic join |
| VISB-02 | Newly spawned agents auto-insert into comms feed and agent card grid without page reload | Card insertion via sync_cards_with_roster + comms stream_insert already pattern-established; needs animation layer and team badge |
</phase_requirements>

## Standard Stack

### Core (Already In Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix LiveView | 1.1.25 | Real-time UI updates, streams | Already installed, provides stream/3 with limit option |
| Jido Signal Bus | (project dep) | Signal routing and subscription | All signals flow through this via TeamBroadcaster |
| Tailwind CSS | (project dep) | Styling, animations | Already used for all components |

### Supporting (Already In Project)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TeamBroadcaster | N/A (app module) | Signal batching with critical bypass | All signal delivery to LiveView |
| AgentColors | N/A (app module) | Deterministic agent coloring | Already called from both cards and comms |
| Topics | N/A (app module) | Centralized topic strings | All subscription management |

### No New Dependencies Required
This phase requires zero new library additions. All functionality is built on existing Phoenix LiveView streams, CSS animations, and JavaScript hooks.

## Architecture Patterns

### Existing Code Map (Critical Files)

```
lib/
├── loomkin/
│   ├── teams/
│   │   ├── team_broadcaster.ex    # Signal batching + critical bypass (204 lines)
│   │   ├── topics.ex              # Topic string generation (78 lines)
│   │   └── comms.ex               # Comms.send_to/3 publishes PeerMessage signals (244 lines)
│   ├── signals/
│   │   └── collaboration.ex       # PeerMessage signal type definition (39 lines)
│   └── tools/
│       └── peer_message.ex        # Tool agents use to send peer messages (29 lines)
├── loomkin_web/
│   ├── live/
│   │   ├── workspace_live.ex      # Main LiveView (3,949 lines) — signal dispatch hub
│   │   ├── agent_comms_component.ex  # Functional component for comms feed (210 lines)
│   │   ├── agent_card_component.ex   # LiveComponent for agent cards (501 lines)
│   │   └── mission_control_panel_component.ex  # Left panel layout (200+ lines)
│   └── agent_colors.ex            # Deterministic color by name hash (26 lines)
└── assets/css/app.css             # All animations and card styles (1,202 lines)
```

### Pattern 1: Signal-to-Comms Pipeline (EXISTING)

**What:** Jido Signals arrive via TeamBroadcaster, get dispatched to `handle_info` clauses, converted to tuple format, routed through `forward_to_cards_and_comms/2`, and inserted into the stream.

**Current flow (working for most signal types):**
```
Signal Bus -> TeamBroadcaster -> {:team_broadcast, batch}
  -> send(self(), {:signal, sig}) for each signal
  -> handle_info(%Jido.Signal{type: "agent.status"}, ...) converts to tuple
  -> handle_info({:agent_status, name, status}, ...) processes
  -> forward_to_cards_and_comms(socket, pubsub_event)
  -> route_event_to_cards_or_comms(socket, event)
  -> stream_insert(:comms_events, event) if type in @comms_event_types
```

**Gap for peer messages:** `collaboration.peer.message` signals currently hit the catch-all at line 998 and are silently dropped. No `handle_info(%Jido.Signal{type: "collaboration.peer.message"})` clause exists.

### Pattern 2: Child Team Subscription (EXISTING)

**What:** When a child team is created, workspace_live auto-subscribes via `subscribe_to_team/2` which registers the team with TeamBroadcaster and synthesizes "joined" events.

**Current flow (already working):**
```
team.child.created signal -> handle_info({:child_team_created, child_team_id})
  -> subscribe_to_team(socket, child_team_id)
    -> PubSub.subscribe for session events
    -> TeamBroadcaster.add_team for signal filtering
    -> Synthesize :agent_spawn events for pre-existing agents
  -> refresh_roster() -> sync_cards_with_roster()
  -> Generate "joined" comms events for new agents
```

This pattern is complete. The gap is that it doesn't include team origin metadata on synthesized events.

### Pattern 3: Agent Card Lifecycle (EXISTING)

**What:** Cards are created via `maybe_spawn_card/2` or `sync_cards_with_roster/1`, stored in `agent_cards` map, and rendered by `AgentCardComponent`.

**Current flow:**
```
Agent status :idle -> maybe_spawn_card -> default_agent_card ->
  assign(agent_cards: Map.put(...)) -> update_card_ordering ->
  stream_insert(:comms_events, spawn_event)
```

Cards have: name, role, team_id, status, content_type, latest_content, last_tool, pending_question, model, budget_used, budget_limit, updated_at.

### Pattern 4: Stream Usage (EXISTING)

**What:** LiveView `stream/3` is initialized in mount with `stream(:comms_events, [])`. Events are added with `stream_insert(:comms_events, event)`.

**Key detail:** The stream is passed to MissionControlPanelComponent as `comms_stream={@streams.comms_events}` and rendered in AgentCommsComponent with `phx-update="stream"`.

**Each event map must have:** `:id` (unique string, uses `Ecto.UUID.generate()`), `:type`, `:agent`, `:content`, `:timestamp`, `:expanded`, `:metadata`.

### Anti-Patterns to Avoid
- **Do NOT add new direct PubSub subscriptions:** All signals must flow through TeamBroadcaster. Phase 02-04 specifically removed the last direct subscriptions.
- **Do NOT use assign for comms events:** The feed MUST use stream/3 to avoid full re-renders. This is already established.
- **Do NOT add signal filtering in workspace_live:** TeamBroadcaster handles team_id filtering. The workspace_live catch-all for unmatched signals is intentional.
- **Do NOT modify the PeerMessage tool or Comms.send_to:** The signal publishing path works correctly. Only the receiving side in workspace_live needs changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stream DOM limiting | Manual DOM pruning via JS | LiveView `stream/3` `:limit` option | Phoenix LiveView 1.1+ supports `:limit` option on stream initialization |
| Auto-scroll detection | Complex IntersectionObserver setup | Phoenix JS Hook with simple scroll position check | scrollTop + scrollHeight comparison is reliable and simple |
| Signal routing | Custom PubSub subscription management | TeamBroadcaster.add_team/2 | Already pre-filters by team_id, handles monitor/cleanup |
| Agent color assignment | Manual color tracking state | AgentColors.agent_color/1 | Deterministic by phash2 -- same input always gives same color |
| Event deduplication | Tracking seen event IDs | Ecto.UUID.generate() for stream IDs | Each stream_insert gets a unique ID; LiveView handles DOM diffing |

**Key insight:** Phoenix LiveView 1.1+ stream/3 accepts a `:limit` option that automatically prunes old items. This was added in LiveView 1.0 and is available in the project's 1.1.25 version. Use `stream(:comms_events, [], limit: -500)` (negative for keeping newest) instead of manual pruning.

## Common Pitfalls

### Pitfall 1: Peer Message Signal Silently Dropped
**What goes wrong:** `collaboration.peer.message` signals arrive at workspace_live but hit the catch-all `handle_info(%Jido.Signal{type: _type}, socket)` at line 998 and are dropped.
**Why it happens:** No dedicated handler clause exists for this signal type.
**How to avoid:** Add a `handle_info(%Jido.Signal{type: "collaboration.peer.message"} = sig, socket)` clause BEFORE the catch-all.
**Warning signs:** Peer messages appear in agent logs but not in the UI comms feed.

### Pitfall 2: Peer Messages Batched Instead of Instant
**What goes wrong:** `collaboration.peer.message` is not in TeamBroadcaster's `@critical_types` MapSet, so it gets batched with 50ms delay. While 50ms is fast, the CONTEXT.md explicitly requires critical-level delivery.
**Why it happens:** TeamBroadcaster's critical types are: permission request, ask-user, error, escalation, team dissolved. Peer messages are currently classified as `:activity` (falls to the `true ->` catch-all in `classify_category/1`).
**How to avoid:** Add `"collaboration.peer.message"` to `@critical_types` in TeamBroadcaster.
**Warning signs:** Peer messages arrive in batches rather than individually.

### Pitfall 3: Stream Limit Direction
**What goes wrong:** Using `stream(:comms_events, [], limit: 500)` keeps the OLDEST 500 items, not the newest.
**Why it happens:** Positive limit keeps items from the beginning; negative limit keeps items from the end.
**How to avoid:** Use `limit: -500` to keep the 500 most recent events.
**Warning signs:** Feed shows only old events and appears "stuck."

### Pitfall 4: Auto-Scroll Breaks on Stream Insert
**What goes wrong:** Each `stream_insert` triggers a DOM patch that may or may not preserve scroll position.
**Why it happens:** LiveView patches the DOM minimally, but the scroll container may not know to scroll down.
**How to avoid:** Use a JS Hook on the scroll container that tracks whether the user is "at bottom" and scrolls down after morphdom patches.
**Warning signs:** Feed requires manual scrolling to see new messages even when user was at the bottom.

### Pitfall 5: Team Badge Without Team Context
**What goes wrong:** Comms events don't carry team origin info, making it impossible to render team badges.
**Why it happens:** Current event maps only have `:agent`, `:type`, `:content`, `:timestamp`, `:metadata`. No `:team_id` or `:team_name` field.
**How to avoid:** Add `:team_id` to the event metadata when creating comms events, especially for events from child teams.
**Warning signs:** Badge renders as empty or "unknown team."

### Pitfall 6: Card Animation Conflicts with LiveView Patching
**What goes wrong:** CSS animations replay on every LiveView DOM patch, causing cards to flash/glow repeatedly.
**Why it happens:** LiveView's morphdom may re-add classes on each patch cycle.
**How to avoid:** Use `animation-fill-mode: forwards` and a one-shot class that is only added on initial insertion, or use a JS hook that adds the animation class only once.
**Warning signs:** Cards continuously pulsing/glowing instead of just on insertion.

## Code Examples

### Example 1: Adding Peer Message Signal Handler

The new handler should be placed in workspace_live.ex between the existing signal handlers and the catch-all (before line 998):

```elixir
# workspace_live.ex — add before the catch-all at line 998
def handle_info(%Jido.Signal{type: "collaboration.peer.message"} = sig, socket) do
  from = sig.data[:from] || "unknown"
  team_id = sig.data[:team_id]
  message = sig.data[:message]

  # Extract the actual content from the message tuple
  {content, target} =
    case message do
      {:peer_message, sender, text} -> {text, nil}
      {:peer_message, sender, text, _opts} -> {text, nil}
      text when is_binary(text) -> {text, nil}
      _ -> {inspect(message), nil}
    end

  event = %{
    id: Ecto.UUID.generate(),
    type: :peer_message,
    agent: from,
    content: content,
    timestamp: DateTime.utc_now(),
    expanded: false,
    metadata: %{team_id: team_id, target: target}
  }

  socket =
    socket
    |> stream_insert(:comms_events, event)
    |> update(:comms_event_count, &(&1 + 1))

  {:noreply, socket}
end
```

### Example 2: Adding peer_message to Critical Types

```elixir
# team_broadcaster.ex — update @critical_types
@critical_types MapSet.new([
  "team.permission.request",
  "team.ask_user.question",
  "team.ask_user.answered",
  "agent.error",
  "agent.escalation",
  "team.dissolved",
  "collaboration.peer.message"  # <-- add this
])
```

### Example 3: Adding peer_message Type Config to Comms Component

```elixir
# agent_comms_component.ex — add to @type_config
peer_message: %{
  icon: "💬",
  accent_border: "rgba(96, 165, 250, 0.30)",
  accent_text: "#93bbfd",
  accent_bg: "rgba(96, 165, 250, 0.08)"
}
```

### Example 4: Stream with Limit (mount change)

```elixir
# workspace_live.ex mount — change line 86
|> stream(:comms_events, [], limit: -500)
```

### Example 5: Auto-Scroll JS Hook

```javascript
// assets/js/hooks/comms_feed_scroll.js
const CommsFeedScroll = {
  mounted() {
    this.isAtBottom = true
    this.newCount = 0

    this.el.addEventListener("scroll", () => {
      const threshold = 50
      const atBottom =
        this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < threshold
      this.isAtBottom = atBottom
      if (atBottom) {
        this.newCount = 0
        this.hideIndicator()
      }
    })

    // Observe new children added to the stream container
    this.observer = new MutationObserver((mutations) => {
      if (this.isAtBottom) {
        this.el.scrollTop = this.el.scrollHeight
      } else {
        // Count new messages and show indicator
        const added = mutations.reduce((count, m) => count + m.addedNodes.length, 0)
        this.newCount += added
        this.showIndicator(this.newCount)
      }
    })

    this.observer.observe(this.el, { childList: true })
  },

  showIndicator(count) {
    let indicator = this.el.parentElement.querySelector("[data-new-messages]")
    if (indicator) {
      indicator.textContent = `${count} new message${count === 1 ? "" : "s"}`
      indicator.classList.remove("hidden")
    }
  },

  hideIndicator() {
    let indicator = this.el.parentElement.querySelector("[data-new-messages]")
    if (indicator) indicator.classList.add("hidden")
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
  }
}

export default CommsFeedScroll
```

### Example 6: Team Badge in Comms Row

```elixir
# In comms_row — add after the agent name button, before the content span
<span
  :if={@event.metadata[:team_id] && @event.metadata[:team_id] != @root_team_id}
  class="flex-shrink-0 text-[9px] font-mono px-1.5 py-0.5 rounded-full bg-surface-2 text-muted"
>
  {short_team_name(@event.metadata[:team_id])}
</span>
```

### Example 7: Card Insertion Animation CSS

```css
/* New card insertion glow — one-shot animation */
@keyframes cardInsertGlow {
  0% { opacity: 0; box-shadow: 0 0 20px var(--card-glow-color, rgba(129, 140, 248, 0.4)); }
  30% { opacity: 1; box-shadow: 0 0 15px var(--card-glow-color, rgba(129, 140, 248, 0.3)); }
  100% { opacity: 1; box-shadow: none; }
}

.agent-card-enter {
  animation: cardInsertGlow 1.5s ease-out forwards;
}

/* Terminated agent dimming */
@keyframes cardTerminate {
  0% { opacity: 1; filter: none; }
  50% { opacity: 0.5; filter: grayscale(80%); }
  100% { opacity: 0; filter: grayscale(100%); }
}

.agent-card-terminated {
  animation: cardTerminate 2.5s ease-out forwards;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct PubSub for all signals | TeamBroadcaster intermediary | Phase 2 (just completed) | All signals flow through broadcaster; no direct subscriptions |
| Manual signal filtering in LiveView | TeamBroadcaster pre-filters by team_id | Phase 2 | workspace_live no longer checks signal_for_workspace? |
| Monolithic workspace_live rendering | Extracted components (AgentCard, AgentComms, MissionControl) | Phase 1 | Components receive data via assigns/streams |
| Append-based message list | LiveView stream/3 for comms | Phase 1 | DOM-efficient updates, no full re-render |

**Key version detail:** Phoenix LiveView 1.1.25 supports `stream/3` with `:limit` option (negative values keep newest N items). This feature was introduced in LiveView 1.0.0 and is stable.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built into Elixir) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/loomkin_web/live/workspace_live_test.exs --trace` |
| Full suite command | `mix test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VISB-01a | Peer message signal creates comms event | unit | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs -x` | No — Wave 0 |
| VISB-01b | Peer message classified as critical in TeamBroadcaster | unit | `mix test test/loomkin/teams/team_broadcaster_test.exs -x` | Yes (needs new test case) |
| VISB-01c | Sub-team peer messages appear in parent comms feed | integration | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs -x` | No — Wave 0 |
| VISB-02a | New agent card inserted on agent_spawn from child team | unit | `mix test test/loomkin_web/live/workspace_live_test.exs -x` | Yes (needs expansion) |
| VISB-02b | Stream limit caps events at ~500 | unit | `mix test test/loomkin_web/live/workspace_live_peer_message_test.exs -x` | No — Wave 0 |
| VISB-02c | AgentCommsComponent renders peer_message type | unit | `mix test test/loomkin_web/live/agent_comms_component_test.exs -x` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/loomkin_web/live/workspace_live_test.exs test/loomkin/teams/team_broadcaster_test.exs --trace`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/loomkin_web/live/workspace_live_peer_message_test.exs` — covers VISB-01a, VISB-01c, VISB-02b
- [ ] `test/loomkin_web/live/agent_comms_component_test.exs` — covers VISB-02c (component render test)
- [ ] New test case in `test/loomkin/teams/team_broadcaster_test.exs` — covers VISB-01b (critical classification)

## Open Questions

1. **Team name/label for badges**
   - What we know: Events carry `team_id` (UUID). The comms feed needs a human-readable label.
   - What's unclear: Is there a team name/label stored in the Manager? Or do we need to derive one (e.g., first 4 chars of UUID, or "sub-1", "sub-2")?
   - Recommendation: Check `Teams.Manager` for a team name field. If none exists, use a short derived label like "sub-1" based on child_teams list index.

2. **Card team_id tracking for badge rendering**
   - What we know: `default_agent_card/2` already sets `:team_id` from cached_agents. AgentCardComponent has access to `@team_id` assign (the active_team_id, not the card's own team).
   - What's unclear: Whether the card's own `team_id` is always set correctly for sub-team agents.
   - Recommendation: Verify in sync_cards_with_roster that sub-team agents get their actual team_id, not the root team_id.

3. **Terminated agent detection**
   - What we know: There's a `team.dissolved` signal and agent status handling. Agent cards have status `:complete`.
   - What's unclear: Is there a specific "agent terminated" signal, or is it inferred from team dissolution / agent status change?
   - Recommendation: Use agent status `:complete` or team dissolution as the trigger. Add a brief CSS animation before removing from the cards map.

## Sources

### Primary (HIGH confidence)
- **workspace_live.ex** — Direct code analysis of signal dispatch pipeline (lines 790-998), subscribe_to_team (lines 2701-2757), forward_to_cards_and_comms (lines 3370-3428)
- **team_broadcaster.ex** — Full source analysis of critical types, batching, and subscriber management
- **agent_comms_component.ex** — Full source analysis of type_config map and stream rendering
- **comms.ex** — Full source analysis of send_to/3 which publishes PeerMessage signals
- **signals/collaboration.ex** — PeerMessage signal type definition with schema

### Secondary (MEDIUM confidence)
- **Phoenix LiveView 1.1.25** — `stream/3` `:limit` option confirmed in project's locked version
- **CONTEXT.md** — User decisions on feed behavior, card animations, and team badges

### Tertiary (LOW confidence)
- **MutationObserver auto-scroll pattern** — Common JS pattern, not verified against this specific LiveView version's DOM patching behavior. May need adjustment based on morphdom behavior.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in project, no new additions needed
- Architecture: HIGH — direct code analysis of existing patterns, clear gap identification
- Pitfalls: HIGH — based on code tracing through actual signal dispatch pipeline
- Auto-scroll JS: MEDIUM — standard pattern but needs testing with LiveView stream patches

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable — no external dependency changes expected)
