# Phase 1: Monolith Extraction - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Decompose workspace_live.ex (4,714 lines, ~90 assigns, 183 handle_event/handle_info clauses, 37 render functions) into focused LiveComponents. The file becomes a pure orchestrator/coordinator under 1,000 lines. No new features — behavior-preserving refactor only.

</domain>

<decisions>
## Implementation Decisions

### Extraction Boundaries
- Extract everything that isn't orchestration — workspace_live.ex becomes a pure router/coordinator
- Command palette (~150 lines) → CommandPaletteComponent (self-contained search/select logic)
- Input bar / composer (~280 lines) → ComposerComponent (message composition, agent picker, queue/scheduler toggles)
- Tab panels (files/diff/graph ~200 lines) → TabPanelComponent (or individual tab components)
- Mission control and solo mode render logic (~450 lines) → separate layout components
- File explorer drawer → extract too (consistency — everything that renders UI becomes a component)
- Existing separate component files (kin_panel, session_switcher, model_selector, etc.) → leave as-is, don't reorganize working components

### State Ownership
- Claude's discretion on how aggressively components own state
- Claude's discretion on component-to-parent communication pattern (Phoenix events vs PubSub)

### Signal Subscriptions
- Claude's discretion on whether components subscribe directly or workspace relays — whatever makes Phase 2 (TeamBroadcaster) easiest to introduce

### Testing Approach
- Claude's discretion on integration test coverage level and whether to add component-level unit tests

### Claude's Discretion
- State ownership split between parent and child components
- Component-to-parent communication pattern
- Signal subscription strategy (direct vs relay vs hybrid)
- Integration test depth (render-only vs smoke interactions)
- Per-component unit tests vs integration-only
- File explorer drawer extraction (extract for consistency, but small)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `agent_card_component.ex` — already separate, handles pause/resume/steer/reply per agent
- `agent_comms_component.ex` — already separate, 15 event types for inter-agent communication feed
- `team_dashboard_component.ex` — already separate, agent list + task list + budget bar
- `team_activity_component.ex` — already separate, rich event cards for tool calls, messages, decisions
- `ask_user_component.ex` — already separate, pending question UI with collective-decide option
- `permission_component.ex` — already separate, tool approval UI
- `chat_component.ex` — already separate, message rendering
- `decision_graph_component.ex` — already separate, SVG DAG visualization
- `kin_panel_component.ex` — agent management panel
- `model_selector_component.ex` — model picker dropdown
- `session_switcher_component.ex` — session list/switch UI
- `message_queue_component.ex` — queue management drawer
- `schedule_message_component.ex` — delayed message scheduler
- `diff_component.ex` — file diff viewer
- `file_tree_component.ex` — file tree rendering
- `file_explorer_drawer_component.ex` — file browser drawer
- `tool_calls_component.ex` — tool execution display
- `trust_policy_component.ex` — trust level selector
- `context_inspector_component.ex` — context window viewer
- `cost_dashboard_live.ex` — cost analytics page (separate LiveView)
- `switch_project_component.ex` — project switcher modal
- `team_cost_component.ex` — team cost breakdown
- `permission_dashboard_component.ex` — permissions overview

### Established Patterns
- LiveComponents use `use LoomkinWeb, :live_component` or `:live_view`
- Components live in `lib/loomkin_web/live/` (not `components/`)
- Components use `update/2` for stateful components, `render/1` for stateless
- Phoenix PubSub for cross-process events, Jido Signal Bus for typed agent signals
- `stream/3` already used for comms_events in mount

### Integration Points
- `workspace_live.ex` is the only consumer of most components — it's the main "shell"
- Router has two actions: `:new` (create session) and `:show` (resume session)
- `start_and_subscribe/3` sets up session, subscribes to PubSub topics
- `terminate/2` cleans up trust policy — must remain in workspace_live.ex

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The key constraint is that this is a pure refactor: identical behavior before and after.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-monolith-extraction*
*Context gathered: 2026-03-07*
