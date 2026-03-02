# Implementation Plan: Epic 5.19 — Decision Graph as Shared Nervous System

> **For**: Claude team executing this epic
> **Read first**: `docs/epic-5.19-decision-graph-nervous-system.md` (architecture + rationale)
> **Master plan**: `~/projects/loom-master-plan.md` (full project context)
> **Repo**: `~/projects/loom`
> **Module namespace**: `Loomkin` (not `Loom`)

---

## Critical Constraints

1. **DO NOT modify context keeper files.** Keepers are the memory layer and must remain untouched:
   - `lib/loomkin/teams/context_keeper.ex` — NO CHANGES
   - `lib/loomkin/teams/context_offload.ex` — NO CHANGES
   - `lib/loomkin/teams/context_retrieval.ex` — NO CHANGES
   - `lib/loomkin/schemas/context_keeper.ex` — NO CHANGES
   - `lib/loomkin/tools/context_offload.ex` — NO CHANGES
   - `lib/loomkin/tools/context_retrieve.ex` — NO CHANGES

2. **No schema migrations needed.** `DecisionNode.metadata` is already a `:map` field. We store `keeper_id` there as a convention, not a column. `DecisionEdge` already has all 7 edge types we need.

3. **Follow existing patterns.** Study these files for conventions:
   - `lib/loomkin/decisions/graph.ex` — Graph API pattern (import Ecto.Query, alias Repo)
   - `lib/loomkin/teams/agent.ex` — PubSub handler pattern (handle_info clauses)
   - `lib/loomkin/teams/comms.ex` — PubSub topic conventions (`team:#{id}`, etc.)
   - `lib/loomkin/teams/supervisor.ex` — Supervision tree pattern
   - `lib/loomkin/decisions/pulse.ex` — Graph query patterns

4. **Test conventions.** Check `test/` directory for patterns. Tests use `Loomkin.Repo` with sandbox mode. Team tests typically mock or start agents via the existing test helpers.

---

## Build Order

Execute tasks sequentially. Each task builds on the previous one.

### Task 1: AutoLogger — Causal Tracing via PubSub

**Create**: `lib/loomkin/decisions/auto_logger.ex`
**Test**: `test/loomkin/decisions/auto_logger_test.exs`

A GenServer that subscribes to team PubSub events and auto-creates graph nodes.

**Step 1a: Study the PubSub events**

Read these files to understand what events are already broadcast:
- `lib/loomkin/teams/comms.ex` — PubSub helper functions and topic naming
- `lib/loomkin/teams/agent.ex` — What events agents broadcast (search for `PubSub.broadcast`)
- `lib/loomkin/teams/manager.ex` — Team lifecycle events
- `lib/loomkin/tools/team_spawn.ex` — Team spawn events
- `lib/loomkin/tools/context_offload.ex` — Offload events (READ ONLY, do not modify)
- `lib/loomkin/tools/peer_create_task.ex` — Task creation events
- `lib/loomkin/tools/peer_complete_task.ex` — Task completion events

Map out every PubSub broadcast and its payload. You need to know what data is available.

**Step 1b: Implement AutoLogger**

```elixir
defmodule Loomkin.Decisions.AutoLogger do
  @moduledoc """
  Subscribes to team PubSub events and auto-creates decision graph nodes
  for lifecycle events, establishing causal tracing.

  Graph nodes created by AutoLogger include `metadata.keeper_id` when
  a relevant context keeper exists, creating a bridge between the
  structured graph (index) and keepers (full-fidelity memory).
  """
  use GenServer

  # Subscribe to team:#{team_id} PubSub topic on start
  # Handle each event type → create appropriate graph node

  # Events to handle:
  # - Agent spawned → :action node, "Agent {name} ({role}) joined team"
  # - Task assigned → :action node, "Task assigned: {title} → {agent}"
  # - Task completed → :outcome node, "Completed: {title}"
  # - Context offloaded → :observation node, "Context offloaded: {topic}"
  #   Include metadata.keeper_id pointing to the new keeper
  # - Team spawned → :action node with edge from triggering goal if identifiable

  # For each node:
  # - Set agent_name from event data
  # - Set session_id from event data if available
  # - Create :leads_to edge from parent goal/action if identifiable
  # - Include metadata.keeper_id when relevant keeper exists
  # - Include metadata.auto_logged: true to distinguish from manual logs
end
```

**Key decisions**:
- AutoLogger is **per-team** (started when team starts, stopped when team dissolves)
- OR **application-level** singleton that filters by team_id from events
- Per-team is cleaner (subscribes only to its team's PubSub topic)
- Start under `Loomkin.Teams.Supervisor` alongside the existing children

**Edge creation heuristic**: When creating a node for a lifecycle event, look for the most recent active `:goal` node in the same session to create a `:leads_to` edge from. If no goal exists, create the node without an edge (orphan nodes are fine — they'll get connected as agents work).

**Acceptance criteria**:
- [ ] AutoLogger starts with team, stops with team
- [ ] At least 5 event types create graph nodes (agent spawn, task assign, task complete, context offload, team spawn)
- [ ] Context offload events include `metadata.keeper_id`
- [ ] `metadata.auto_logged: true` on all auto-created nodes
- [ ] Edges link to parent goals when identifiable
- [ ] Tests: each event type creates correct node type + edges

---

### Task 2: Graph API Additions

**Modify**: `lib/loomkin/decisions/graph.ex`
**Test**: Update existing `test/loomkin/decisions/graph_test.exs`

Add support for team-scoped queries and keeper-linked node creation.

**Step 2a: Add team-aware filters**

The graph currently filters by `session_id`. Add `team_id` and cross-session support:

```elixir
# In apply_node_filters/2, add:
defp apply_node_filters(query, [{:team_id, team_id} | rest]) do
  # Join through sessions that belong to this team, OR
  # Filter nodes where metadata contains team_id
  # (Depends on whether sessions have team_id — check schema)
  query |> apply_node_filters(rest)
end

# Cross-session: all nodes regardless of session
defp apply_node_filters(query, [{:cross_session, true} | rest]) do
  query |> apply_node_filters(rest)
  # Simply don't add session_id filter
end
```

**Important**: Check `lib/loomkin/schemas/session.ex` to see if sessions have a `team_id` field. If not, AutoLogger should store `team_id` in `metadata.team_id` on nodes it creates, and the filter should query metadata.

**Step 2b: Add helper for keeper-linked nodes**

```elixir
def add_node_with_keeper(attrs, keeper_id) when is_binary(keeper_id) do
  attrs = put_in(attrs, [:metadata, :keeper_id], keeper_id)
  add_node(attrs)
end
```

**Step 2c: Add edge-walking helpers**

```elixir
# Walk downstream from a node through specific edge types
def walk_downstream(node_id, edge_types, opts \\ []) do
  max_depth = Keyword.get(opts, :max_depth, 5)
  # BFS/DFS through edges, return list of {node, depth, edge_type}
end

# Walk upstream (reverse edges) to find ancestors
def walk_upstream(node_id, edge_types, opts \\ []) do
  # Same but following edges in reverse (to_node_id → from_node_id)
end

# Find nodes connected to a given node through specific edge types
def connected_nodes(node_id, edge_types) do
  # Both directions, single hop
end
```

These walkers are used by Broadcaster (Task 3) and Cascade (Task 4).

**Acceptance criteria**:
- [ ] `list_nodes(team_id: id)` returns nodes scoped to a team
- [ ] `add_node_with_keeper/2` stores keeper_id in metadata
- [ ] `walk_downstream/3` traverses edges by type with depth limit
- [ ] `walk_upstream/3` traverses reverse edges
- [ ] Tests: team filtering, keeper metadata, graph walking

---

### Task 3: Discovery Broadcaster

**Create**: `lib/loomkin/decisions/broadcaster.ex`
**Test**: `test/loomkin/decisions/broadcaster_test.exs`

A GenServer that watches for new observation nodes and notifies agents whose goals are relevant.

**Step 3a: Understand the flow**

```
Agent logs :observation node (via decision_log tool or AutoLogger)
  ↓
Broadcaster detects new node (via PubSub or polling)
  ↓
Walks :enables/:requires edges from observation → find connected :goal nodes
  ↓
For each connected goal with status :active, find owning agent (agent_name field)
  ↓
Send PubSub notification to that agent:
  {:discovery_relevant, %{
    observation_id: obs_id,
    observation_title: "...",
    goal_id: goal_id,
    goal_title: "...",
    keeper_id: metadata.keeper_id || nil,  # for deep-dive
    source_agent: who_logged_it
  }}
  ↓
Receiving agent sees notification in handle_info → can choose to:
  - Read graph node summary (already has title + description)
  - Call context_retrieve on keeper_id for full context
```

**Step 3b: Implement Broadcaster**

```elixir
defmodule Loomkin.Decisions.Broadcaster do
  @moduledoc """
  Watches for new observation/outcome nodes in the decision graph and
  proactively notifies agents whose active goals are connected via
  :enables or :requires edges.

  This is the "push" layer — instead of agents polling for relevant
  discoveries, the graph routes knowledge to where it's needed.

  Discovery notifications include keeper_id when available, so agents
  can follow the reference to get full context from keepers.
  """
  use GenServer
end
```

**How to detect new nodes**: Two options:
1. **PubSub**: Have `Graph.add_node/1` broadcast `{:graph_node_added, node}` on a PubSub topic. Broadcaster subscribes. **Preferred** — real-time, follows existing PubSub patterns.
2. **Polling**: Periodically query for nodes newer than last check. Simpler but adds latency.

Go with option 1. Add a PubSub broadcast to `Graph.add_node/1`:

```elixir
# In graph.ex, after successful insert:
def add_node(attrs) do
  # ... existing code ...
  case Repo.insert(changeset) do
    {:ok, node} ->
      Phoenix.PubSub.broadcast(Loomkin.PubSub, "decision_graph", {:node_added, node})
      {:ok, node}
    error -> error
  end
end
```

**Edge-walking strategy**: Use `Graph.walk_upstream/3` (from Task 2) with edge types `[:enables, :requires]` to find connected goal nodes. Limit depth to 3 to avoid expensive traversals.

**Rate limiting**: Don't spam agents. Debounce notifications — if 5 observations are logged in quick succession about the same goal, batch them into one notification.

**Acceptance criteria**:
- [ ] Graph.add_node broadcasts to PubSub topic
- [ ] Broadcaster subscribes and processes new observation/outcome nodes
- [ ] Edge-walking finds connected active goals
- [ ] Notifications sent to owning agents via team PubSub
- [ ] Notifications include keeper_id when available
- [ ] Debouncing prevents notification spam
- [ ] Tests: observation → goal found → agent notified, with and without keeper_id

---

### Task 4: Confidence Cascade

**Create**: `lib/loomkin/decisions/cascade.ex`
**Test**: `test/loomkin/decisions/cascade_test.exs`

Propagates confidence warnings downstream when a node's confidence drops below threshold.

**Step 4a: Implement Cascade**

```elixir
defmodule Loomkin.Decisions.Cascade do
  @moduledoc """
  Propagates confidence warnings through the decision graph.

  When a node's confidence is set or updated below the threshold (default 50),
  walks :requires/:blocks edges downstream and flags dependent nodes as
  potentially unstable. Notifies owning agents so they can re-evaluate.

  Agents can query the keeper referenced in the low-confidence node's metadata
  to get the full conversation context for re-evaluation.
  """

  @default_threshold 50

  def check_and_propagate(node_id, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    # 1. Get the node
    # 2. If confidence < threshold, walk downstream
    # 3. For each downstream node, update metadata.upstream_uncertainty
    # 4. Notify owning agents
  end
end
```

**Trigger**: Hook into `Graph.update_node/2`. After a successful update where `confidence` changed:

```elixir
# In graph.ex update_node/2, after successful update:
if Map.has_key?(attrs, :confidence) do
  Cascade.check_and_propagate(node.id)
end
```

**Notification payload**:

```elixir
{:confidence_warning, %{
  source_node_id: low_confidence_node_id,
  source_title: "...",
  source_confidence: 35,
  affected_node_id: your_dependent_node_id,
  affected_title: "...",
  keeper_id: metadata.keeper_id || nil,  # for re-evaluation
  edge_path: [:requires, :leads_to]  # how they're connected
}}
```

**Acceptance criteria**:
- [ ] Confidence drop below threshold triggers cascade
- [ ] Downstream nodes found via `:requires`/`:blocks` edges (depth-limited)
- [ ] `metadata.upstream_uncertainty` set on affected nodes
- [ ] Owning agents notified via PubSub
- [ ] Notifications include keeper_id for re-evaluation
- [ ] Cascade is idempotent (re-running doesn't duplicate warnings)
- [ ] Tests: cascade propagation, depth limiting, agent notification

---

### Task 5: Enhanced ContextBuilder — Prior Attempts + Cross-Session

**Modify**: `lib/loomkin/decisions/context_builder.ex`
**Test**: Update `test/loomkin/decisions/context_builder_test.exs`

**Step 5a: Study current ContextBuilder**

Read `lib/loomkin/decisions/context_builder.ex` carefully. Understand:
- How `build/2` assembles context sections
- Token budget allocation
- What sections exist today (active goals, recent decisions, session context)

**Step 5b: Add "Prior Attempts & Lessons" section**

Query for `:revisit` and `:superseded` nodes that match the current session's topics:

```elixir
defp prior_attempts_section(session_id) do
  # Get revisit nodes (flagged for re-examination)
  revisits = Graph.list_nodes(node_type: :revisit, status: :active)

  # Get superseded/abandoned decisions (things that were tried and didn't work)
  abandoned = Graph.list_nodes(status: :abandoned)
  superseded = Graph.list_nodes(status: :superseded)

  # Format as context section:
  # "## Prior Attempts & Lessons
  #  - [REVISIT] Auth token format (confidence: 30) — needs re-evaluation
  #  - [ABANDONED] OAuth approach — rejected due to complexity (keeper: abc-123)
  #  - [SUPERSEDED] REST API → replaced by GraphQL (keeper: def-456)"
end
```

**Step 5c: Add cross-session goal awareness**

Currently `build/2` filters by `session_id`. Add an option to include goals from other sessions:

```elixir
def build(session_id, opts \\ []) do
  cross_session = Keyword.get(opts, :cross_session, false)

  goals = if cross_session do
    Graph.list_nodes(node_type: :goal, status: :active)  # all sessions
  else
    Graph.list_nodes(node_type: :goal, status: :active, session_id: session_id)
  end

  # ... rest of build ...
end
```

**Step 5d: Include keeper references in context output**

When a graph node has `metadata.keeper_id`, include it in the formatted output so the agent knows it can dig deeper:

```
## Active Goals
- Implement user authentication (confidence: 85)
  → Deep context available in keeper abc-123
```

**Acceptance criteria**:
- [ ] "Prior Attempts & Lessons" section added to context output
- [ ] Revisit, abandoned, and superseded nodes surfaced
- [ ] Cross-session goal queries work (opt-in flag)
- [ ] Keeper references included when nodes have `metadata.keeper_id`
- [ ] Token budget respected (new sections don't blow the budget)
- [ ] Tests: prior attempts section, cross-session, keeper references

---

### Task 6: Agent Integration — Handle New PubSub Messages

**Modify**: `lib/loomkin/teams/agent.ex`
**Test**: Update `test/loomkin/teams/agent_test.exs`

**Step 6a: Study existing handle_info clauses**

Read `lib/loomkin/teams/agent.ex`. Find existing `handle_info` clauses to understand the pattern for handling PubSub messages. Look for how agents currently process incoming messages.

**Step 6b: Add handlers for discovery and confidence warnings**

```elixir
# Discovery notification — another agent's observation is relevant to our goal
def handle_info({:discovery_relevant, payload}, state) do
  # Inject into agent's pending context for next LLM turn:
  # "Discovery from {source_agent}: {observation_title} may be relevant to your goal: {goal_title}"
  # If keeper_id present: "Full context available via context_retrieve on keeper {keeper_id}"
  {:noreply, inject_pending_update(state, :discovery, payload)}
end

# Confidence warning — upstream decision is uncertain
def handle_info({:confidence_warning, payload}, state) do
  # Inject warning: "Warning: upstream decision '{source_title}' has low confidence ({confidence}).
  # Your work on '{affected_title}' may be affected. Consider re-verifying."
  {:noreply, inject_pending_update(state, :confidence_warning, payload)}
end
```

**How `inject_pending_update` works**: Check if the agent already has a pattern for queuing pending updates between LLM turns. If so, follow that pattern. If not, add a `pending_updates` list to agent state that gets injected as a system message on the next LLM call.

**Acceptance criteria**:
- [ ] Agents handle `:discovery_relevant` messages
- [ ] Agents handle `:confidence_warning` messages
- [ ] Messages are queued and injected on next LLM turn (not interrupting current work)
- [ ] Tests: agent receives and processes both message types

---

### Task 7: Supervision & Startup

**Modify**: `lib/loomkin/teams/supervisor.ex` (or wherever team children are started)

**Step 7a: Start AutoLogger and Broadcaster with each team**

```elixir
# When a team starts, also start:
children = [
  # ... existing children ...
  {Loomkin.Decisions.AutoLogger, team_id: team_id},
  {Loomkin.Decisions.Broadcaster, team_id: team_id}
]
```

**Note**: `Cascade` doesn't need its own process — it's triggered synchronously from `Graph.update_node/2`. It's a module with functions, not a GenServer.

**Step 7b: Ensure clean shutdown**

When a team dissolves (`team_dissolve` tool), AutoLogger and Broadcaster should terminate gracefully. Check how existing team children are shut down and follow the same pattern.

**Acceptance criteria**:
- [ ] AutoLogger starts with team
- [ ] Broadcaster starts with team
- [ ] Both shut down cleanly on team dissolve
- [ ] Supervision restarts them on crash (transient restart strategy)

---

### Task 8: Tests — Integration Suite

**Create**: `test/loomkin/decisions/nervous_system_integration_test.exs`

End-to-end test that validates the full flow:

```elixir
test "observation triggers discovery notification to relevant agent" do
  # 1. Create a team with two agents
  # 2. Agent A logs a :goal node
  # 3. Agent B logs an :observation node with :enables edge to Agent A's goal
  # 4. Assert Agent A receives {:discovery_relevant, ...} via PubSub
end

test "context offload creates graph node with keeper_id" do
  # 1. Agent offloads context → keeper created
  # 2. Assert AutoLogger created :observation node
  # 3. Assert node has metadata.keeper_id matching the keeper
end

test "low confidence cascades to dependent nodes" do
  # 1. Create goal → decision → action chain with :requires edges
  # 2. Update decision confidence to 30
  # 3. Assert action node gets metadata.upstream_uncertainty
  # 4. Assert owning agent notified
end

test "ContextBuilder includes prior attempts from other sessions" do
  # 1. In session A, log a decision then mark it :abandoned
  # 2. In session B, build context with cross_session: true
  # 3. Assert abandoned decision appears in "Prior Attempts" section
end

test "keeper_id in graph nodes enables two-tier retrieval" do
  # 1. Create keeper with messages about auth
  # 2. Create graph :decision node with metadata.keeper_id
  # 3. Agent queries graph → gets structured summary
  # 4. Agent follows keeper_id → gets full context via smart retrieval
end
```

**Acceptance criteria**:
- [ ] Full flow tests pass: event → auto-log → broadcast → agent notification
- [ ] Keeper integration tests pass: graph node → keeper_id → smart retrieval
- [ ] Cascade tests pass: confidence drop → downstream notification
- [ ] Cross-session tests pass: prior attempts surface in new sessions
- [ ] No existing tests broken

---

## File Reference

### Existing files you MUST read before starting

| File | Why |
|------|-----|
| `lib/loomkin/decisions/graph.ex` | Graph API — you'll extend this |
| `lib/loomkin/decisions/pulse.ex` | Query patterns for graph analysis |
| `lib/loomkin/decisions/context_builder.ex` | Context injection — you'll extend this |
| `lib/loomkin/schemas/decision_node.ex` | Node schema (metadata is a :map field) |
| `lib/loomkin/schemas/decision_edge.ex` | Edge schema + types |
| `lib/loomkin/teams/agent.ex` | Agent GenServer — you'll add handle_info clauses |
| `lib/loomkin/teams/comms.ex` | PubSub conventions — follow these patterns |
| `lib/loomkin/teams/supervisor.ex` | Team supervision — you'll add children here |
| `lib/loomkin/teams/manager.ex` | Team lifecycle — understand spawn/dissolve flow |
| `lib/loomkin/tools/decision_log.ex` | How agents currently write to graph |
| `lib/loomkin/agent_loop.ex` | The ReAct loop — understand where context is injected |

### Existing files you must NOT modify

| File | Why |
|------|-----|
| `lib/loomkin/teams/context_keeper.ex` | Keeper is the memory layer — untouchable |
| `lib/loomkin/teams/context_offload.ex` | Offload logic is correct as-is |
| `lib/loomkin/teams/context_retrieval.ex` | Retrieval API is correct as-is |
| `lib/loomkin/schemas/context_keeper.ex` | Keeper schema is correct as-is |
| `lib/loomkin/tools/context_offload.ex` | Tool interface is correct as-is |
| `lib/loomkin/tools/context_retrieve.ex` | Tool interface is correct as-is |

---

## Success Criteria

When this epic is complete:

1. A new agent joining a team can read the decision graph and understand WHY 3 agents are working on auth — because lifecycle events auto-created a causal trail.

2. When researcher-1 discovers "the API uses OAuth not JWT", agents working on related auth goals get notified automatically — they don't have to ask.

3. When someone sets confidence to 30 on "database choice: SQLite", agents building queries downstream get a warning — they can pause and re-evaluate using the full conversation context from keepers.

4. When a lead plans a new task, the graph tells them "this was tried before in session X, it was abandoned because Y" — and they can dig into the keeper for the full discussion.

5. All of this happens WITHOUT modifying a single line of context keeper code. Keepers remain the full-fidelity memory. The graph becomes the index that routes agents to the right keeper at the right time.
