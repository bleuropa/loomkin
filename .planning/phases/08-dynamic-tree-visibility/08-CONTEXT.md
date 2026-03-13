# Phase 8: Dynamic Tree Visibility - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Nested sub-teams at arbitrary depth auto-appear in the workspace UI via recursive signal subscription. The toolbar gains a tree popover showing live team hierarchy with agent counts. The ChildTeamCreated signal is moved to Manager.create_sub_team/3 with team_name and depth in its payload. Leader agent crash correctly terminates child teams via GenServer-held monitor refs. Spawn safety gates (budget check before spawning) and leader research protocol are out of scope (Phases 9 and 10).

</domain>

<decisions>
## Implementation Decisions

### Agent tree panel location and design
- The tree lives in the toolbar — the existing flat `<select>` team switcher is replaced by a tree trigger
- The trigger is **hidden until at least one sub-team exists**; no UI change until a child spawns
- When clicked, opens a **dropdown popover** anchored below the toolbar (closes on outside click)
- Each tree node shows: **team name + live agent count** — depth shown by indent level only, no explicit badge
- Clicking a node **switches the active team** (same behavior as the current dropdown, but from the tree)

### Recursive subscription
- Child subscription follows the **same recursive pattern**: when ChildTeamCreated fires, workspace_live subscribes to that team — if it later spawns children, those fire their own ChildTeamCreated signals and workspace_live subscribes again
- Max depth of 2 (already enforced in Manager) keeps the recursion bounded
- **Tree state replaces the flat list**: `child_teams` assign becomes a `%{parent_id => [child_ids]}` map so the LiveView can render the hierarchy without Manager lookups at render time
- On team dissolution: workspace_live walks the tree map to find the dissolved team and all its known descendants, unsubscribes from each, and removes them from the map — does NOT rely on cascading Dissolved signals from Manager

### OTP crash → child termination
- **Leader agent GenServer holds monitor refs** to the child team supervisor PIDs it spawns (stored in agent state alongside the spawning context)
- When the leader crashes, its GenServer process terminates — the monitor teardown (or a linked terminate/2 path) calls Manager.dissolve_team for each monitored child team before OTP restarts the leader
- Leader **restarts fresh with no child teams** — no auto-restore; it re-runs its planning logic and re-spawns as needed
- This prevents zombie teams from accumulating across leader restart cycles

### ChildTeamCreated signal
- Signal published from **Manager.create_sub_team/3** (not from TeamSpawn tool) — single canonical source
- TeamSpawn tool's existing publish call is **removed**
- Signal schema extended: add `team_name: string` and `depth: integer` fields alongside existing `team_id` and `parent_team_id`
- workspace_live renders the new tree node immediately from signal data — no Manager.get_team_meta round-trip needed

### Claude's Discretion
- Exact popover styling, positioning, and animation (open/close transition)
- Whether the toolbar trigger shows the active team name or a generic "Teams" label
- Whether a depth-2 node is visually indented further or uses a different connector character
- Comms feed event for sub-team spawn/dissolve (whether to emit one, styling)

</decisions>

<specifics>
## Specific Ideas

- "Similar to a list of models currently" — the toolbar trigger should feel consistent with other toolbar controls (same height, same hover/focus style), just with a richer popover
- Tree popover should feel like a rich select menu — compact rows, keyboard-navigable if possible, no heavy modal chrome

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `workspace_live.ex` — existing `subscribe_to_team/2` function handles signal subscription for a team. Phase 8 calls this recursively when ChildTeamCreated fires.
- `Manager.create_sub_team/3` — already stores `depth` and `parent_team_id` in ETS meta; just needs the publish call added and signal schema extended.
- `Manager.dissolve_team/1` — already cascades depth-first dissolution; signal Dissolved is already published per team. workspace_live needs to match this with its own recursive unsubscribe walk.
- `Signals.Team.ChildTeamCreated` — existing signal at `"team.child.created"`, currently schema has `team_id` and optional `parent_team_id`. Add `team_name` and `depth` fields.
- `Signals.Team.Dissolved` — already published from Manager; workspace_live already handles it to remove from child_teams list (needs recursive walk upgrade).

### Established Patterns
- Critical signal classification (Phase 2, Phase 6): ChildTeamCreated should be classified as critical in TeamBroadcaster for instant delivery — same as approval gate and ask_user signals.
- `@child_teams` flat list → `team_tree` map: the existing assign and all references to it need updating. Pattern mirrors how `pending_questions` replaced `pending_question` in Phase 7.
- Popover pattern for toolbar dropdown: no existing popover component — planner will design it. Should reuse surface-2/border-subtle tokens consistent with existing dropdowns.

### Integration Points
- `lib/loomkin/teams/manager.ex` — add `Loomkin.Signals.publish(ChildTeamCreated.new!(...))` inside `create_sub_team/3` after ETS insertion.
- `lib/loomkin/tools/team_spawn.ex` — remove the existing `ChildTeamCreated` publish block (lines ~100-108).
- `lib/loomkin/signals/team.ex` — extend `ChildTeamCreated` schema with `team_name` and `depth` fields.
- `lib/loomkin/teams/agent.ex` — add `spawned_child_teams: []` field to agent state (list of `{team_id, monitor_ref}` tuples). Add monitor setup in `handle_call({:team_spawned, ...})`. Add `handle_info({:DOWN, ref, :process, ...})` to trigger child team dissolution.
- `lib/loomkin_web/live/workspace_live.ex` — replace `child_teams: []` assign with `team_tree: %{}` map. Update `handle_info({:child_team_created, ...})` to insert into map. Update `handle_info` for Dissolved to walk and prune descendants. Replace `<select>` dropdown render with tree popover LiveComponent.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 08-dynamic-tree-visibility*
*Context gathered: 2026-03-08*
