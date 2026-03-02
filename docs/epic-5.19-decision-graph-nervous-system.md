# Epic 5.19: Decision Graph as Shared Nervous System

> **Priority**: P0 — builds on all existing Phase 5 infrastructure
> **Depends on**: Epics 5.1-5.18 (all complete)
> **Principle**: Graph is the index/nervous system. Keepers are the memory. They enhance each other.

---

## Origin

This epic originates from `~/documents/decision-graph-vision.md`, which identified that the
decision graph today is essentially a journal — agents log what they decided and why. The real
unlock is making it the **shared nervous system** of the entire agent mesh, while preserving
Context Keepers as the irreplaceable full-fidelity memory layer.

---

## The Problem

### Two Layers, Zero Integration

Loomkin has two powerful coordination layers that currently don't talk to each other:

| Layer | What it is | Scope | Writes |
|-------|-----------|-------|--------|
| **Decision Graph** | Structured DAG — 7 node types, typed edges, confidence scores | Session-scoped (`session_id` FK) | Manual (agent calls `decision_log`) + rare auto (debates, role changes) |
| **Context Keepers** | Full-fidelity conversation buffers in GenServer processes | Team-scoped (`team_id`) | Automatic (offload when context > 60% of model limit) |

The graph never consults keepers. Keepers never write to the graph. They're parallel.

### What's Missing (from the vision doc)

1. **Causality is invisible** — When an agent spawns a sub-team because it discovered something mid-task, that causal chain lives in scattered PubSub messages. A new agent joining later can't understand WHY things are happening.

2. **Knowledge routing is ad-hoc** — Agents can ask questions (`peer_ask_question`), but can't say "I learned X, and it's relevant to goal Y that agent Z is pursuing." Discovery is pull-only.

3. **Confidence propagation doesn't exist** — If an agent marks a decision at confidence 40 and another agent depends on that decision, nothing alerts the downstream agent. The graph has the edges but nobody walks them.

4. **Planning ignores history** — Before a lead decomposes a task, it doesn't query the graph for prior attempts, abandoned approaches, or discovered constraints.

---

## The Complementary Model

### One-Sentence Architecture

> **The graph knows WHAT happened and WHO cares. Keepers know the FULL STORY. Graph nodes point to keepers via `keeper_id`. Fast questions hit the graph. Deep questions follow the reference to keepers.**

### How They Enhance Each Other

```
                    DECISION GRAPH                          CONTEXT KEEPERS
              (Index / Nervous System)                    (Memory / Archive)
         ┌─────────────────────────────┐          ┌─────────────────────────────┐
         │                             │          │                             │
         │  goal ──→ decision ──→ action│  keeper_id │  Full 200-message thread   │
         │    │         │         │     │────────────→│  about auth debate with    │
         │    │      option(rejected)   │          │  every argument, code        │
         │    │         │              │          │  snippet, and tradeoff       │
         │    └──→ observation         │          │                             │
         │                             │          │  Smart query: "Why was      │
         │  Confidence: 85             │          │  OAuth rejected?" → focused │
         │  Agent: coder-1             │          │  answer from full context   │
         │  Status: active             │          │                             │
         └─────────────────────────────┘          └─────────────────────────────┘

         FAST: "What did we decide?"               DEEP: "Why? Show me everything."
         STRUCTURED: nodes, edges, scores           RAW: full conversation fidelity
         ROUTING: who cares about this?             PAYLOAD: here's the full context
```

### Data Flow Principles

1. **Graph references keepers, not the other way around** — `metadata.keeper_id` on graph nodes points to relevant keepers. Keepers don't need to know about the graph.

2. **Keepers are never modified by graph operations** — The graph reads from keepers (via smart retrieval) but never writes to or alters keeper state.

3. **Graph is the routing layer, keepers are the payload** — Discovery broadcasting walks graph edges to find WHO cares, then points them to the relevant keeper for full context.

4. **Two-tier retrieval** — Fast path hits the graph for structured answers. Deep path follows `keeper_id` to get full-fidelity context from keepers.

---

## Research Findings

### Decision Graph — Current State

**Module**: `Loomkin.Decisions.Graph` (`lib/loomkin/decisions/graph.ex`)
**Schema**: `Loomkin.Schemas.DecisionNode` (`lib/loomkin/schemas/decision_node.ex`)

- **7 node types**: goal, decision, option, action, outcome, observation, revisit
- **7 edge types**: leads_to (default), chosen, rejected, requires, blocks, enables, supersedes
- **Confidence**: 0-100 integer, optional, no semantic definition in code
- **Metadata**: map field, currently unused — this is where `keeper_id` will go
- **Agent attribution**: `agent_name` field added Feb 28 migration
- **Context injection**: `ContextBuilder.build/2` injects active goals + recent decisions into system prompt (capped at 1024 tokens / 4096 chars)
- **Pulse reports**: `Pulse.generate/1` flags coverage gaps, low-confidence nodes, stale nodes

**Key gap**: Only debates and role changes auto-write to graph. Everything else requires agents to explicitly call `decision_log`. Most lifecycle events (spawn, task assign, offload) leave no graph trace.

### Context Keepers — Current State

**Module**: `Loomkin.Teams.ContextKeeper` (`lib/loomkin/teams/context_keeper.ex`)
**Schema**: `Loomkin.Schemas.ContextKeeper` (`lib/loomkin/schemas/context_keeper.ex`)

- **Storage**: Full message lists (role + content), topics, token counts, metadata
- **Offload trigger**: 60% of model context limit → split at topic boundary → spawn keeper
- **Smart retrieval**: Single cheap LLM call over stored context, keyword fallback
- **Cross-agent access**: Any agent can query any keeper in the team via Registry
- **Persistence**: Debounced SQLite writes (50ms), reload on init, archived on team dissolve
- **Knowledge routing integration**: `QueryRouter.ask` auto-enriches questions with keeper context (5s timeout, graceful fallback)

**Key strength**: Keepers are independent processes, discoverable via Registry, and auto-enriched into knowledge routing. This must not be disrupted.

---

## Capability Design

### Capability 1: Causal Tracing

> Graph writes the edges, keepers hold the evidence.

When lifecycle events happen, auto-create graph nodes with edges linking them to the triggering context:

| Event | Graph Node | Edge | Keeper Link |
|-------|-----------|------|-------------|
| `team_spawn` | `:action` "Spawned team: {name}" | `:leads_to` from triggering goal | `keeper_id` of lead's context at spawn time |
| `context_offload` | `:observation` "Context offloaded: {topic}" | `:leads_to` from active goal | `keeper_id` of the new keeper |
| `peer_message` (significant) | `:observation` "Discovery: {summary}" | `:enables` to relevant goals | `keeper_id` if message references offloaded context |
| `task_assigned` | `:action` "Task assigned: {title} → {agent}" | `:leads_to` from parent goal | None (lightweight) |
| `task_completed` | `:outcome` "Completed: {title}" | `:leads_to` from task action | `keeper_id` if agent offloaded during task |
| `agent_spawned` | `:action` "Agent {name} ({role}) joined" | `:leads_to` from team spawn | None (lightweight) |

**Implementation**: Hook into existing PubSub events in `Loomkin.Teams.Comms`. A new module subscribes to team events and writes graph nodes. No changes to keepers.

### Capability 2: Discovery Broadcasting

> Graph discovers who cares, keepers deliver the payload.

When an agent logs an `:observation` node:

1. **Graph walker** queries edges from the observation → find connected goals (via `:enables`/`:requires` reverse-walk)
2. For each connected goal, find the owning agent (via `agent_name` field)
3. Send lightweight PubSub notification: `{:discovery_relevant, observation_id, goal_id, keeper_id}`
4. Receiving agent can choose to:
   - Read the graph node summary (fast, structured)
   - Query the referenced keeper via smart retrieval (deep, full context)

**Implementation**: New `Loomkin.Decisions.Broadcaster` GenServer. Subscribes to graph write events. Does edge-walking. Sends PubSub notifications. Keepers are only involved as optional deep-dive targets.

### Capability 3: Confidence Cascades

> Graph propagates signals, keepers provide evidence for re-evaluation.

When a node's confidence is set or updated below a threshold (default 50):

1. **Cascade walker** follows `:requires`/`:blocks` edges downstream
2. Flag dependent nodes as `metadata.upstream_uncertainty: true`
3. Notify owning agents: `{:confidence_warning, node_id, upstream_confidence, keeper_id}`
4. Agents can then query the referenced keeper for the full discussion that led to the low-confidence decision

**Implementation**: Hook into `Graph.update_node/2`. When confidence changes, trigger cascade. Builds on Pulse (which already finds low-confidence nodes) but makes it real-time and edge-aware.

### Capability 4: Graph-Informed Planning

> Graph provides structure, keepers provide depth.

Before a lead agent decomposes a task:

1. **ContextBuilder** queries graph for `revisit` and `superseded` nodes matching the topic
2. Inject structured summary: "Prior attempts: X was tried (confidence 30, abandoned). Y was rejected (reason in keeper K)."
3. If lead needs more, it calls `context_retrieve` on the referenced keeper

**Implementation**: Extend `Loomkin.Decisions.ContextBuilder.build/2` to include prior-attempt context. Add a new section alongside "Active Goals" and "Recent Decisions": "Prior Attempts & Lessons."

### Capability 5: Cross-Session Memory

> Graph is the fast lookup, keepers are the archive.

This is largely already built. The remaining piece:

1. **ContextBuilder** should query across ALL sessions (not just current) for active goals
2. Archived keepers (status: `:archived`) should be discoverable by new sessions
3. Graph nodes with `keeper_id` create a durable link: new session reads graph → follows keeper references → gets full prior context

**Implementation**: Remove session-scoping from some `ContextBuilder` queries. Add `list_nodes(team_id: id)` filter alongside existing `session_id` filter.

---

## Files Affected

### New Files

| File | Purpose | Est. LOC |
|------|---------|----------|
| `lib/loomkin/decisions/auto_logger.ex` | Subscribes to PubSub, auto-writes lifecycle events to graph | ~200 |
| `lib/loomkin/decisions/broadcaster.ex` | Walks graph edges on new observations, notifies relevant agents | ~150 |
| `lib/loomkin/decisions/cascade.ex` | Propagates confidence changes through edges | ~120 |

### Modified Files

| File | Change | Est. Delta |
|------|--------|-----------|
| `lib/loomkin/decisions/graph.ex` | Add `add_node_with_keeper/2`, team_id filter support | +30 |
| `lib/loomkin/decisions/context_builder.ex` | Add "Prior Attempts" section, cross-session queries, keeper-enriched context | +60 |
| `lib/loomkin/decisions/pulse.ex` | Add cascade-aware low-confidence detection | +30 |
| `lib/loomkin/schemas/decision_node.ex` | Document `metadata.keeper_id` convention (no schema change needed — metadata is already a map) | +5 (comments) |
| `lib/loomkin/teams/agent.ex` | Handle `:discovery_relevant` and `:confidence_warning` PubSub messages | +40 |
| `lib/loomkin/teams/supervisor.ex` | Start AutoLogger and Broadcaster under supervision | +10 |
| `lib/loomkin/application.ex` | (if AutoLogger is app-level, not team-level) | +5 |

### Untouched (Explicitly)

- `lib/loomkin/teams/context_keeper.ex` — No changes. Keepers remain the memory layer.
- `lib/loomkin/teams/context_offload.ex` — No changes to offload logic.
- `lib/loomkin/teams/context_retrieval.ex` — No changes. Agents already have smart retrieval.
- `lib/loomkin/tools/context_*.ex` — No tool changes. Existing tools sufficient.

---

## Total Estimated Effort

| Component | New LOC | Modified LOC | Total |
|-----------|---------|-------------|-------|
| AutoLogger (causal tracing) | ~200 | +15 (supervisor) | ~215 |
| Broadcaster (discovery) | ~150 | +40 (agent handlers) | ~190 |
| Cascade (confidence) | ~120 | +30 (pulse) | ~150 |
| ContextBuilder (planning + cross-session) | — | +60 | ~60 |
| Graph API additions | — | +30 | ~30 |
| Tests | ~400 | — | ~400 |
| **Total** | **~870** | **~175** | **~1,045** |

---

## Acceptance Criteria

- [ ] Lifecycle events (team spawn, agent spawn, task assign/complete, context offload) auto-create graph nodes
- [ ] Auto-created nodes include `metadata.keeper_id` when a relevant keeper exists
- [ ] New observations trigger edge-walking to find and notify agents with related active goals
- [ ] Notified agents can follow `keeper_id` to get full context via existing smart retrieval
- [ ] Low-confidence nodes propagate warnings downstream through `requires`/`blocks` edges
- [ ] ContextBuilder injects prior-attempt context (revisit/superseded nodes) into planning prompts
- [ ] ContextBuilder can query across sessions (not just current session)
- [ ] All new modules are supervised (crash recovery)
- [ ] Keeper modules remain completely untouched
- [ ] Tests cover: auto-logging, broadcasting, cascades, cross-session queries, keeper references
