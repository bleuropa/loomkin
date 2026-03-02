# Architecture

**122 source files. ~20,000 LOC application code. ~13,000 LOC tests. 925+ test cases across 83 files.**

## System Overview

```
┌──────────────────────────────────────────────────────────┐
│                      INTERFACES                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   CLI (Owl)   │  │ LiveView Web │  │ Headless API │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         └─────────────────┼─────────────────┘            │
├───────────────────────────┼──────────────────────────────┤
│  Session Layer            │                              │
│  ┌────────────────────────┴───────────────────────────┐  │
│  │ Session GenServer (per-conversation)                │  │
│  │  ├── Jido.AI.Agent (ReAct reasoning loop)          │  │
│  │  ├── Context Window (token-budgeted history)       │  │
│  │  ├── Decision Graph (persistent reasoning memory)  │  │
│  │  └── Permission Manager (per-tool approval)        │  │
│  └────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────┤
│  Tool Layer (28 Jido Actions)                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────────┐   │
│  │FileRead │ │FileWrite│ │FileEdit │ │ FileSearch   │   │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├──────────────┤   │
│  │  Shell  │ │   Git   │ │SubAgent │ │ContentSearch │   │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├──────────────┤   │
│  │DecisionLog│DecisionQuery│DirList │ │LspDiagnostics│   │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├──────────────┤   │
│  │TeamSpawn│ │TeamAssign│ │TeamDiss.│ │TeamProgress  │   │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├──────────────┤   │
│  │PeerMsg  │ │PeerDisc.│ │PeerReview│ │PeerClaimRgn │   │
│  ├─────────┤ ├─────────┤ ├─────────┤ ├──────────────┤   │
│  │PeerTask │ │PeerAsk  │ │PeerAnswer│ │CtxOffload   │   │
│  └─────────┘ └─────────┘ └─────────┘ └──────────────┘   │
├──────────────────────────────────────────────────────────┤
│  Intelligence Layer                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐  │
│  │Decision Graph│ │  Repo Intel  │ │ Context Window  │  │
│  │ (7 node types│ │ (ETS index,  │ │ (token budget,  │  │
│  │  DAG in      │ │  tree-sitter │ │  keeper offload, │  │
│  │  SQLite)     │ │  + file      │ │  zero loss)     │  │
│  │              │ │  watcher)    │ │                 │  │
│  └──────────────┘ └──────────────┘ └─────────────────┘  │
├──────────────────────────────────────────────────────────┤
│  Protocol Layer                                          │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐  │
│  │  MCP Server  │ │  MCP Client  │ │   LSP Client    │  │
│  │ (expose tools│ │ (consume     │ │ (diagnostics    │  │
│  │  to editors) │ │  ext. tools) │ │  from lang      │  │
│  │              │ │              │ │  servers)       │  │
│  └──────────────┘ └──────────────┘ └─────────────────┘  │
├──────────────────────────────────────────────────────────┤
│  LLM Layer: req_llm (16+ providers, 665+ models)        │
│  Anthropic │ OpenAI │ Google │ Groq │ xAI │ Bedrock │…  │
├──────────────────────────────────────────────────────────┤
│  Telemetry + Observability                               │
│  Event emission │ ETS metrics │ Cost dashboard (/dash)   │
└──────────────────────────────────────────────────────────┘
```

### Interfaces

Three ways to interact with Loomkin — CLI, Phoenix LiveView web UI, and headless API — all backed by the same session GenServer. The web UI provides streaming chat, file tree browsing, unified diffs, and an interactive SVG decision graph, all without writing JavaScript.

### Session Layer

Each conversation is a GenServer managing a `Jido.AI.Agent` (ReAct reasoning loop), a token-budgeted context window, a persistent decision graph, and a per-tool permission manager. Sessions can be saved and resumed from SQLite.

### Tool Layer

28 built-in tools implemented as `Jido.Action` modules — file operations, shell execution, git, LSP diagnostics, decision logging, sub-agent search, team management, and peer communication.

### Intelligence Layer

The three systems that give Loomkin persistent intelligence across sessions: a decision graph that remembers goals and tradeoffs, a tree-sitter-powered repository index, and a token-aware context window that offloads overflow to Keeper processes instead of summarizing it away.

### Protocol Layer

MCP server exposes tools to editors (VS Code, Cursor, Zed). MCP client consumes external tools (Tidewave, HexDocs). LSP client surfaces compiler errors/warnings from language servers.

### LLM Layer

All LLM calls go through [req_llm](https://github.com/agentjido/req_llm) — 16+ providers, 665+ models, streaming, tool calling, cost tracking.

---

## The Decision Graph

Inspired by [Deciduous](https://github.com/juspay/deciduous), Loomkin maintains a persistent DAG of decisions, goals, and outcomes across coding sessions:

- **7 node types**: goal, decision, option, action, outcome, observation, revisit
- **Typed edges**: leads_to, chosen, rejected, requires, blocks, enables, supersedes
- **Confidence tracking**: each node carries a 0-100 confidence score
- **Context injection**: before every LLM call, active goals and recent decisions are injected into the system prompt — token-budgeted so it never blows the context window
- **Pulse reports**: health checks that surface coverage gaps, stale decisions, and low-confidence areas

The graph lives in SQLite (via Ecto) and travels with your project. When you come back to a codebase after a week, Loomkin remembers what you were trying to accomplish, what approaches were tried, and why certain options were rejected.

### The Nervous System (Epic 5.19)

The decision graph isn't just a passive journal — it's an active shared nervous system for the agent mesh:

- **Auto-logging** — lifecycle events (agent spawns, task assignments, task completions, context offloads) automatically create graph nodes linked to parent goals. New agents can trace the causal chain of why work is happening.
- **Discovery broadcasting** — when an agent creates an observation or outcome relevant to another agent's active goal, the graph walks edges via BFS and notifies the interested agent with keeper references for deep context retrieval.
- **Confidence cascades** — when a decision's confidence drops, downstream nodes connected via `:requires`/`:blocks` edges are flagged with `upstream_uncertainty`. Owning agents receive real-time alerts, preventing work from building on shaky foundations.
- **Graph-informed planning** — the ContextBuilder injects "Prior Attempts & Lessons" (revisit, abandoned, superseded nodes) into planning prompts so leaders decomposing tasks see "this was tried before" instead of rediscovering dead ends.
- **Cross-session memory** — the graph links to archived keepers from past sessions, enabling new teams to learn from history.

We chose to implement the decision graph natively in Elixir rather than shelling out to the Rust-based Deciduous CLI. Ecto gives us the same SQLite persistence with composable queries, and LiveView can render the graph interactively without a separate process. Full credit to the Deciduous project for pioneering the concept of structured decision tracking for AI agents.

---

## The Jido Foundation

Loomkin is built on the [Jido](https://github.com/agentjido/jido) agent ecosystem. Rather than reinventing agent infrastructure, we stand on the shoulders of a thoughtfully designed Elixir-native framework:

- **[jido_action](https://github.com/agentjido/jido_action)** — Every Loomkin tool is a `Jido.Action` with declarative schemas, automatic validation, and composability. No manual parameter parsing, no hand-written JSON Schema.
- **[jido_ai](https://github.com/agentjido/jido_ai)** — The `Jido.AI.ToolAdapter` bridges our actions to LLM tool schemas in one line. `Jido.AI.Agent` provides the ReAct reasoning strategy that drives the agent loop.
- **[req_llm](https://github.com/agentjido/req_llm)** — 16+ LLM providers, 665+ models, streaming, tool calling, cost tracking. The engine room of every LLM call Loomkin makes.

The Jido ecosystem saves thousands of lines of code and provides battle-tested infrastructure for the hard problems (tool dispatch, schema validation, provider normalization) so Loomkin can focus on the interesting problems (decision graphs, context intelligence, repo understanding).

---

## Project Structure

```
loomkin/
├── lib/
│   ├── loomkin/
│   │   ├── application.ex          # OTP supervision tree
│   │   ├── agent.ex                # Jido.AI.Agent definition (tools + config)
│   │   ├── config.ex               # ETS-backed config (TOML + env vars)
│   │   ├── repo.ex                 # Ecto Repo (SQLite)
│   │   ├── tool.ex                 # Shared helpers (safe_path!, param access)
│   │   ├── project_rules.ex        # LOOMKIN.md parser
│   │   ├── session/
│   │   │   ├── session.ex          # Core GenServer + PubSub broadcasting
│   │   │   ├── manager.ex          # Start/stop/find/list sessions
│   │   │   ├── persistence.ex      # SQLite CRUD for sessions + messages
│   │   │   ├── context_window.ex   # Token budget allocation + compaction
│   │   │   └── architect.ex        # Two-model architect/editor workflow
│   │   ├── agent_loop.ex           # Shared ReAct loop (sessions + team agents)
│   │   ├── teams/
│   │   │   ├── supervisor.ex       # Registry + DynamicSupervisor + RateLimiter
│   │   │   ├── agent.ex            # Agent GenServer (team member runtime)
│   │   │   ├── manager.ex          # Team lifecycle API (create, spawn, dissolve)
│   │   │   ├── role.ex             # Role definitions (lead, researcher, coder, reviewer, tester)
│   │   │   ├── rate_limiter.ex     # Token bucket + per-team/per-agent budget
│   │   │   ├── comms.ex            # PubSub utilities for team communication
│   │   │   ├── context.ex          # ETS shared state per team
│   │   │   ├── context_keeper.ex   # Holds offloaded context at full fidelity
│   │   │   ├── context_offload.ex  # Topic boundary detection + offloading logic
│   │   │   ├── context_retrieval.ex # Cross-agent context discovery + retrieval
│   │   │   ├── tasks.ex            # Task CRUD + scheduling
│   │   │   ├── model_router.ex     # Model selection + opt-in escalation
│   │   │   ├── cost_tracker.ex     # Per-team/per-agent cost accounting
│   │   │   ├── query_router.ex     # Cross-agent question routing
│   │   │   ├── table_registry.ex   # ETS table lifecycle management
│   │   │   ├── templates.ex        # Team composition templates
│   │   │   ├── pricing.ex          # Model cost lookups
│   │   │   ├── migration.ex        # Team data migrations
│   │   │   ├── debate.ex           # Multi-agent debate protocol
│   │   │   ├── pair_mode.ex        # Coder + reviewer pair programming
│   │   │   ├── learning.ex         # Team pattern learning
│   │   │   ├── cluster.ex          # Distributed team support
│   │   │   └── distributed.ex      # Cross-node agent communication
│   │   ├── tools/                  # Jido.Action tool modules
│   │   │   ├── registry.ex         # Tool discovery + Jido.Exec dispatch
│   │   │   ├── file_read.ex        # Core tools (12)
│   │   │   ├── file_write.ex
│   │   │   ├── file_edit.ex
│   │   │   ├── file_search.ex
│   │   │   ├── content_search.ex
│   │   │   ├── directory_list.ex
│   │   │   ├── shell.ex
│   │   │   ├── git.ex
│   │   │   ├── lsp_diagnostics.ex
│   │   │   ├── decision_log.ex
│   │   │   ├── decision_query.ex
│   │   │   ├── sub_agent.ex
│   │   │   ├── team_spawn.ex       # Team lead tools (4)
│   │   │   ├── team_assign.ex
│   │   │   ├── team_dissolve.ex
│   │   │   ├── team_progress.ex
│   │   │   ├── peer_message.ex     # Peer communication tools (9)
│   │   │   ├── peer_discovery.ex
│   │   │   ├── peer_review.ex
│   │   │   ├── peer_claim_region.ex
│   │   │   ├── peer_create_task.ex
│   │   │   ├── peer_ask_question.ex
│   │   │   ├── peer_answer_question.ex
│   │   │   ├── peer_forward_question.ex
│   │   │   ├── peer_change_role.ex
│   │   │   ├── context_offload.ex  # Context mesh tools (2)
│   │   │   └── context_retrieve.ex
│   │   ├── decisions/              # Deciduous-inspired decision graph
│   │   │   ├── graph.ex            # CRUD + queries
│   │   │   ├── pulse.ex            # Health reports
│   │   │   ├── narrative.ex        # Timeline generation
│   │   │   └── context_builder.ex  # LLM context injection
│   │   ├── repo_intel/             # Repository intelligence
│   │   │   ├── index.ex            # ETS file catalog
│   │   │   ├── repo_map.ex         # Symbol extraction + ranking
│   │   │   ├── tree_sitter.ex      # Tree-sitter + enhanced regex parser (7 langs)
│   │   │   ├── context_packer.ex   # Tiered context assembly
│   │   │   └── watcher.ex          # OS-native file watcher with debounce
│   │   ├── mcp/                    # Model Context Protocol
│   │   │   ├── server.ex           # Expose tools to editors via MCP
│   │   │   ├── client.ex           # Consume external MCP tools
│   │   │   └── client_supervisor.ex
│   │   ├── lsp/                    # Language Server Protocol
│   │   │   ├── client.ex           # JSON-RPC stdio LSP client
│   │   │   ├── protocol.ex         # LSP message encoding/decoding
│   │   │   └── supervisor.ex       # LSP process supervision
│   │   ├── telemetry.ex            # Event emission helpers
│   │   ├── telemetry/
│   │   │   └── metrics.ex          # ETS-backed real-time metrics
│   │   ├── release.ex              # Release tasks (migrate, create_db)
│   │   ├── permissions/            # Tool permission system
│   │   │   ├── manager.ex
│   │   │   └── prompt.ex
│   │   └── schemas/                # Ecto schemas (SQLite)
│   ├── loomkin_web/                   # Phoenix LiveView web UI
│   │   ├── endpoint.ex             # Bandit HTTP endpoint
│   │   ├── router.ex               # Browser routes + LiveDashboard
│   │   ├── components/
│   │   │   ├── core_components.ex  # Flash, form, input, button helpers
│   │   │   ├── layouts.ex          # Layout module
│   │   │   └── layouts/            # Root + app HTML templates
│   │   ├── controllers/
│   │   │   ├── error_html.ex       # HTML error pages
│   │   │   └── error_json.ex       # JSON error responses
│   │   └── live/                   # LiveView components
│   │       ├── workspace_live.ex         # Main split-screen layout
│   │       ├── chat_component.ex         # Streaming chat with markdown
│   │       ├── file_tree_component.ex    # Recursive file browser
│   │       ├── diff_component.ex         # Unified diff viewer
│   │       ├── decision_graph_component.ex # Interactive SVG DAG
│   │       ├── model_selector_component.ex # Multi-provider model picker
│   │       ├── session_switcher_component.ex # Session management
│   │       ├── permission_component.ex   # Tool approval modal
│   │       ├── terminal_component.ex     # Shell output renderer
│   │       ├── cost_dashboard_live.ex    # Telemetry + cost dashboard
│   │       ├── team_dashboard_component.ex # Team orchestration UI
│   │       ├── team_activity_component.ex  # Real-time agent activity feed
│   │       └── team_cost_component.ex    # Per-team budget + spend tracking
│   └── loomkin_cli/                   # CLI interface
│       ├── main.ex                 # Escript entry point
│       ├── interactive.ex          # REPL loop
│       └── renderer.ex             # ANSI markdown + diff rendering
├── assets/                         # Frontend assets
│   ├── js/app.js                   # LiveSocket + hooks (ShiftEnterSubmit, ScrollToBottom)
│   ├── css/app.css                 # Tailwind dark theme
│   └── tailwind.config.js          # Tailwind configuration
├── priv/repo/migrations/           # SQLite migrations
├── test/                           # 925+ tests across 83 files
├── config/                         # Dev/test/prod/runtime config
└── docs/                           # Architecture + migration docs
```
