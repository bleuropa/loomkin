# Phase 3: Live Comms Feed - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Agent-to-agent peer messages appear in the comms feed for all teams including dynamically spawned sub-teams, and newly spawned agents auto-insert into the UI without a page reload. No filtering controls, no message editing, no conversation threading — pure visibility of live agent communication.

</domain>

<decisions>
## Implementation Decisions

### Sub-team Message Visibility
- Flat mixed feed — all messages from root + sub-teams interleaved chronologically in one stream
- Sub-team messages get a subtle team badge/label to show origin team
- Auto-subscribe to sub-team signals when ChildTeamCreated signal arrives (workspace_live already does this pattern)
- Peer messages are critical signals — under 1 second from emission to feed appearance (TeamBroadcaster already bypasses batching for critical types)

### Agent Card Insertion
- New agent cards fade in with brief glow/pulse highlight (1-2 seconds) at the end of the grid
- Cards appended at end — existing cards don't move, no layout shift
- Sub-team agent cards get a subtle team badge matching the comms feed badge style
- Terminated agents show dimmed/grayed "terminated" state for 2-3 seconds, then fade out

### Feed Density
- All 15+ event types visible by default — full mission control visibility
- No filtering controls in this phase (filtering UI is a separate capability for a future phase)
- Auto-scroll when user is at bottom; hold position with "N new messages" indicator when scrolled up
- Feed capped at ~500 events via stream management — older events removed from DOM to prevent browser memory issues

### Color Identity
- Independent per-agent colors via existing AgentColors phash2 — team identity shown via badges, not colors
- Same agent color used identically in card and comms feed (both already call AgentColors.agent_color)
- Current 10-color palette is sufficient — team badges are the primary identifier, not color alone

### Claude's Discretion
- Team badge visual design (pill, dot, tag — whatever communicates team origin clearly without clutter)
- Team badge depth indicator design (optional, if it helps distinguish root vs child vs grandchild)
- Auto-scroll detection mechanism (scroll position tracking approach)
- Stream cap implementation (LiveView stream limit vs manual pruning)
- Card fade/glow animation implementation (CSS transitions vs LiveView hooks)
- Card removal animation timing and approach

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AgentCommsComponent` — functional component rendering 15 event types with color-coded rows and type_config map
- `AgentCardComponent` — stateful LiveComponent with memoized markdown rendering, per-agent card with `phx-click="focus_card_agent"`
- `AgentColors` — deterministic color by name hash (10 colors, phash2-based)
- `TeamBroadcaster` — batching GenServer with critical signal bypass; peer messages should be classified as critical
- `Topics` module — centralized topic string generation for subscriptions
- `stream(:comms_events, [])` — already initialized in mount; `stream_insert(:comms_events, event)` used for adding events

### Established Patterns
- Sub-team subscription: `subscribe_to_team/2` already handles child teams, including synthesizing "joined" events for pre-existing agents
- Comms event structure: events have `:type`, agent name, content — `stream_insert` adds to LiveView stream
- Agent spawn events: workspace_live already creates `:agent_spawn` comms events and inserts them
- ChildTeamCreated signal: `Loomkin.Signals.Team.ChildTeamCreated` already published from `TeamSpawn` tool
- Session child team signal: `session.child_team.available` signal already defined

### Integration Points
- `workspace_live.ex` `handle_info({:team_broadcast, batch})` — entry point for all signal processing
- `workspace_live.ex` `subscribe_to_team/2` — already subscribes to child teams via TeamBroadcaster
- `AgentCommsComponent` `@type_config` — add new event types here if needed
- `AgentCardComponent` `render/1` — uses `AgentColors.agent_color(assigns.card.name)` for card coloring

</code_context>

<specifics>
## Specific Ideas

- Feed should feel like a mission control "social layer" — seeing everything agents are saying to each other in real-time
- Team badges should be subtle enough not to clutter the feed but visible enough to tell which sub-team a message came from
- Card insertion should be smooth — no jarring layout jumps when new agents appear

</specifics>

<deferred>
## Deferred Ideas

- Feed filtering controls (by event type, by team) — future phase
- Message threading / conversation grouping — future phase
- Feed search — future phase

</deferred>

---

*Phase: 03-live-comms-feed*
*Context gathered: 2026-03-07*
