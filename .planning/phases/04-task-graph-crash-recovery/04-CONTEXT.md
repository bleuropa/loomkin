# Phase 4: Task Graph & Crash Recovery - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual task dependency graph showing blocked-by relationships, and OTP agent crash status reflected in agent cards with recovered state — all updating live without page refresh. No manual task management controls (reassign, cancel, unblock) — pure visibility of task dependencies and crash recovery.

</domain>

<decisions>
## Implementation Decisions

### Task Graph Placement
- Lives in the sidebar graph tab alongside the existing DecisionGraphComponent
- Sub-tabs within the graph tab: "Tasks" and "Decisions" — both accessible, neither lost
- Tab label stays "Graph"

### Task Graph Visual Style
- SVG DAG like DecisionGraphComponent — layered layout with directed edges for blocked-by relationships
- Reuses the proven visual language (bezier edges, arrowheads) for consistency across the app
- Each task node displays: title, colored status indicator, and assigned agent name
- Dependency edges visually distinguish `:blocks` (solid arrows) from `:informs` (dashed) — makes critical path clear at a glance
- Highlight the critical path (longest chain of blocking dependencies) with emphasized edges

### Task Graph Interactivity
- Click a task node to see full details (description, owner, dependencies, result) in a detail panel below the graph — consistent with DecisionGraphComponent's click-to-inspect pattern
- Subtle transitions when task states change (node color transitions smoothly, completed dependency edges fade or change color)

### Crash State on Agent Cards
- Crashed-but-recovering: red pulsing dot with "crashed" text during crash window. When OTP restarts it, transitions to amber "recovering" briefly, then back to normal status. Builds on existing `:error` styling
- Permanently dead (max restarts exceeded): card stays visible in red "failed" state with persistent banner/badge saying "max restarts exceeded". Does not disappear silently. Human sees it needs attention
- Recovery history: persistent crash count badge (e.g., "1x crashed") that persists for the session — human can see which agents are unstable

### Crash Events in Comms Feed
- Crash and recovery appear as system-level events in the comms feed (like agent spawn events). Uses a distinct event type color
- Gives a timeline record of crashes and recoveries

### Signal Delivery Timing
- Crash/recovery signals: critical — instant delivery, bypassing 50ms batch window. Human should see a crash immediately
- Task status changes (assigned, completed, unblocked): batched is fine — 50ms window prevents flickering on rapid updates. Current `:activity` classification works
- 2-second target for crash-to-recovered-on-card is the hard target (per roadmap success criteria). Achievable with Process.monitor + critical signal delivery

### Task Graph Loading
- Full graph loaded on mount — fetch all current tasks + dependencies from DB and render the full graph when sidebar graph tab opens
- Live updates layer on top via signals

### Claude's Discretion
- Exact sub-tab UI design within the graph tab
- Task node sizing and spacing in the DAG layout
- Critical path highlighting algorithm and visual treatment
- Crash count badge visual design
- "Recovering" transition timing and animation
- How to adapt DecisionGraphComponent patterns vs build fresh TaskGraphComponent

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DecisionGraphComponent` (`lib/loomkin_web/live/decision_graph_component.ex`): Full SVG DAG renderer with layered layout, cubic bezier edges, arrowheads, node coloring, click-to-inspect, agent filter buttons. Pattern can be adapted for task graph
- `AgentCardComponent` (`lib/loomkin_web/live/agent_card_component.ex`): Already has `:error` status with red dot and `card-error` CSS class. Needs new `:crashed` and `:recovered` statuses added
- `SidebarPanelComponent` (`lib/loomkin_web/live/sidebar_panel_component.ex`): Has `:graph` tab infrastructure, currently renders DecisionGraphComponent. Needs sub-tab routing added
- `TeamBroadcaster` (`lib/loomkin/teams/team_broadcaster.ex`): Batching GenServer with `@critical_types` MapSet for instant delivery. Crash signals need to be added to critical types
- `Teams.Tasks` context (`lib/loomkin/teams/tasks.ex`): `blocked_task_ids/1`, `list_available/1`, `add_dependency/3`, `auto_schedule_unblocked/1` — full dependency data layer exists

### Established Patterns
- Signal classification in TeamBroadcaster: `classify_category/1` routes by signal type prefix; critical types bypass batching via MapSet lookup
- Agent status broadcasting: `set_status_and_broadcast/2` in Agent GenServer updates status and publishes signal — new crash/recovered statuses follow this pattern
- Comms event types: `AgentCommsComponent` `@type_config` map defines color/icon per event type — new crash/recovery event types added here
- LiveComponent click-to-inspect: DecisionGraphComponent pattern of detail panel below graph on node click

### Integration Points
- `workspace_live.ex` `handle_info({:team_broadcast, batch})`: entry point for all signal processing — needs handlers for new crash/recovery signals
- `SidebarPanelComponent` `render_tab(:graph, assigns)`: currently renders only DecisionGraphComponent — needs sub-tab routing to TaskGraphComponent
- `Teams.Agent` `handle_info({:DOWN, ...})`: currently broadcasts `:idle` on loop crash — needs to broadcast `:crashed` instead, with new signal type
- `Loomkin.Teams.AgentSupervisor` (DynamicSupervisor): agents are `:temporary` restart — need Process.monitor from a watcher to detect process-level crashes
- `Loomkin.Signals.Agent`: no crash/recovered signal types defined yet — new signal types needed
- Task signals in `Comms.broadcast_task_event/2`: TaskAssigned, TaskCompleted, TaskFailed, TaskStarted already exist — need to trigger graph refresh

</code_context>

<specifics>
## Specific Ideas

- Task graph should use the same visual language as DecisionGraphComponent — consistent "graph" experience across both sub-tabs
- Crash state should feel urgent — red pulsing dot and "crashed" text should grab attention without being alarming
- The persistent crash count badge helps identify chronically unstable agents over a session
- Critical path highlighting helps humans understand what's actually holding up team progress

</specifics>

<deferred>
## Deferred Ideas

- Manual task actions from graph (reassign, cancel, unblock) — future intervention phase
- Task filtering/search in graph view — future phase
- Task time estimates and progress bars — future phase

</deferred>

---

*Phase: 04-task-graph-crash-recovery*
*Context gathered: 2026-03-07*
