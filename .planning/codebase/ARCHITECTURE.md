# Architecture

**Analysis Date:** 2026-03-07

## Pattern Overview

**Overall:** Multi-agent teams-first ReAct (Reasoning + Acting) architecture with persistent decision graph memory, context mesh for overflow management, and OTP-based supervision for fault tolerance.

**Key Characteristics:**
- Parameterized agent loop decoupled from session/team management (any GenServer can use `Loomkin.AgentLoop`)
- Hierarchical team structures with elected lead agents managing task decomposition and coordination
- Persistent PostgreSQL decision DAG (7 node types) that survives across sessions
- Context windowing with token budget allocation across system prompt, decision context, repo map, and conversation history
- Jido Signal Bus for typed, event-driven inter-agent communication with automatic subscription filtering
- Region-level locking for concurrent file edits with intent broadcasting across teams

## Layers

**Core Agent Loop (`Loomkin.AgentLoop`):**
- Purpose: Reusable ReAct agent loop compatible with any caller (Session, Teams.Agent, or custom)
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop.ex`, `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop/`
- Contains: ReAct iteration (LLM call → tool classification → tool execution → checkpoint), rate limiting, budget tracking, permission checks, context offload triggers
- Depends on: `Loomkin.LLM` (model calling), `Loomkin.Tools.Registry` (tool lookup), `Jido.Exec` (tool execution), `Loomkin.Permissions.HookRunner` (pre/post hooks)
- Used by: `Loomkin.Session`, `Loomkin.Teams.Agent`, strategy modules (`Loomkin.AgentLoop.Strategies.*`)

**Session Layer (`Loomkin.Session`):**
- Purpose: Single-user solo agent session with history persistence and model management
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/session/`
- Contains: `session.ex` (GenServer), `architect.ex` (session composition), `context_window.ex` (token budgeting), `manager.ex` (pid lookup), `persistence.ex` (DB serialization)
- Depends on: `Loomkin.AgentLoop`, `Loomkin.Repo`, `Loomkin.Decisions`, `Loomkin.RepoIntel`
- Used by: Web UI (`LoomkinWeb.WorkspaceLive`), CLI

**Team Layer (`Loomkin.Teams`):**
- Purpose: Multi-agent orchestration with election, consensus, task delegation, and cross-team queries
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/`
- Contains: `agent.ex` (per-agent GenServer), `supervisor.ex` (team spawning/cleanup), `role.ex` (lead/specialist config), `context_keeper.ex` (overflow Keeper), `comms.ex` (peer messaging), `consensus_policy.ex` (voting), `tasks.ex` (task graph), `learning.ex` (knowledge transfer between agents)
- Depends on: `Loomkin.AgentLoop`, `Jido.Signal.Bus`, `Loomkin.Teams.Manager`, `Loomkin.Decisions`
- Used by: `Loomkin.Session` (for team_id), team tools (team_spawn, team_assign)

**Decision Graph Layer (`Loomkin.Decisions`):**
- Purpose: Persistent reasoning memory spanning multiple sessions and teams
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/decisions/`
- Contains: `graph.ex` (DAG operations), `context_builder.ex` (inject decision context), `auto_logger.ex` (capture decisions), `cascade.ex` (propagate constraints), `narrative.ex` (human-readable summary)
- Depends on: `Loomkin.Repo`, `Loomkin.Schemas.DecisionNode/Edge`
- Used by: `Loomkin.Session.ContextWindow` (inject context), team agents (log decisions), `Loomkin.Tools.DecisionLog/Query`

**Tool System (`Loomkin.Tools`):**
- Purpose: Executable actions available to agents (file ops, git, shell, peer communication, team management)
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/tools/`
- Contains: 28 tools split into `@solo_tools`, `@peer_tools` (team collaboration), `@lead_tools` (team management), all using Jido.Action pattern
- Depends on: `Jido.Exec`, `Loomkin.Tool` (path validation), permissions hooks, Elixir standard library
- Used by: `Loomkin.AgentLoop` (tool execution), registry in `tools/registry.ex`

**Web UI Layer (`LoomkinWeb`):**
- Purpose: LiveView-based workspace and monitoring dashboards
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin_web/`
- Contains: `live/` (6 LiveView pages), `components/` (25+ reusable Phoenix components), `controllers/` (auth, webhooks), `helpers/`
- Depends on: `Loomkin.Session`, `Loomkin.Teams`, `Loomkin.Decisions`, `Phoenix.LiveView`
- Used by: Browsers at http://localhost:4200

**Persistence Layer (`Loomkin.Repo`, `Loomkin.Schemas`):**
- Purpose: PostgreSQL schema and Ecto migrations
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/schemas/`, `priv/repo/migrations/`
- Contains: 12 schemas (Session, Message, DecisionNode, DecisionEdge, TeamTask, AuthToken, etc.), changesets, associations
- Depends on: Ecto, PostgreSQL
- Used by: All persistence-backed modules

**Auth Layer (`Loomkin.Auth`):**
- Purpose: OAuth token storage and provider authentication
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/auth/`
- Contains: `token_store.ex` (encrypted persistence), `oauth_server.ex` (PKCE flow), `provider_registry.ex`, `provider.ex` (abstract), provider implementations (Google, OpenAI, Anthropic)
- Depends on: `Assent`, `ReqLLM`, `Loomkin.Repo`
- Used by: `Loomkin.LLM` (inject tokens), web auth controller

**Repository Intelligence (`Loomkin.RepoIntel`):**
- Purpose: Index, map, and search codebase structure for context enrichment
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/repo_intel/`
- Contains: `index.ex` (tree-sitter symbol cache), `watcher.ex` (file change detection), `repo_map.ex` (repo structure summary)
- Depends on: `file_system`, tree-sitter, LSP client
- Used by: `Loomkin.Session.ContextWindow` (inject repo map)

**Channels Layer (`Loomkin.Channels`):**
- Purpose: Chat platform integrations (Telegram, Discord)
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/channels/`
- Contains: `telegram/`, `discord/`, webhook handlers, message routing
- Depends on: `telegex`, `nostrum`, webhook adapters
- Used by: External chat platforms, web route `/api/webhooks/telegram`

## Data Flow

**Solo Session Flow (User → Assistant):**

1. User sends message via `LoomkinWeb.WorkspaceLive` (web UI) → `Loomkin.Session.send_message/2`
2. Session loads conversation history from `Loomkin.Repo` (persisted messages)
3. Session calls `Loomkin.AgentLoop.run/2` with:
   - Messages (user input + history)
   - Tools from `Loomkin.Tools.Registry.all/0`
   - System prompt + decision context + repo map (built by `ContextWindow.build_messages/4`)
   - Callbacks for events (`:tool_executing`, `:tool_complete`, `:stream_delta`, etc.)
4. AgentLoop calls `Loomkin.LLM.stream_text/3` → `ReqLLM` → LLM API
5. LLM responds with text or tool calls
6. AgentLoop checks permissions via `Loomkin.Permissions.HookRunner` (pre-tool hooks)
7. For each tool call:
   - Lookup tool module in registry via `Jido.AI.ToolAdapter.lookup_action/2`
   - Execute via `Jido.Exec.run/4` with context (project_path, session_id, team_id, etc.)
   - Track file reads in process dictionary for read-before-write enforcement
   - Run post-tool hooks (`HookRunner.run_post_hooks/3`)
   - Record tool result message
8. Loop continues until LLM gives `:final_answer` or `:max_iterations`
9. Session persists messages to DB, emits `:new_message` event on `Loomkin.SignalBus`
10. LiveView updates UI with streaming response and tool execution results

**Team Collaboration Flow:**

1. Lead agent (in team) calls `Loomkin.Tools.TeamSpawn` → creates sub-agents via `Loomkin.Teams.Supervisor`
2. Each agent is `Loomkin.Teams.Agent` GenServer with elected role (lead/specialist/observer)
3. Lead agent calls `Loomkin.Tools.TeamAssign` → emits task to team via `Jido.Signal.Bus`
4. Agents subscribe to `team.**` signals in `Comms.task_listener/2`
5. Specialist agents run `AgentLoop` independently (same loop as solo, with team_id in context)
6. Inter-agent comms via peer tools:
   - `PeerAskQuestion` → query broadcast, collect answers
   - `ContextRetrieve` → fetch from team Keepers (overflow context)
   - `PeerReview` → peer feedback gates
   - `CollectiveDecision` → consensus with voting
7. Cost tracking per agent via `Teams.CostTracker`
8. Team supervisor monitors health; crashed agents restarted by OTP

**Decision Graph Flow:**

1. During session, `Loomkin.Decisions.AutoLogger` listens to agent events on `Loomkin.SignalBus`
2. Captures key decisions (tool calls, revisions, consensus votes) and inserts `DecisionNode` rows
3. Connects nodes via `DecisionEdge` with relationship type (`:depends_on`, `:contradicts`, etc.)
4. `Loomkin.Decisions.ContextBuilder` queries graph and injects summary into system prompt for next session
5. Graph survives session end; can be queried later via `Loomkin.Tools.DecisionQuery` or dashboard

**Context Mesh (Overflow) Flow:**

1. `Loomkin.Session.ContextWindow.build_messages/4` counts tokens in messages
2. If history exceeds budget, `Loomkin.Teams.ContextOffload.maybe_offload/1` invokes
3. Messages moved from agent's message list → `ContextKeeper` GenServer (per team)
4. Keeper stores large message batches in-memory (not in agent struct)
5. Future calls to `ContextRetrieve` fetch from Keeper by relevance score
6. Zero summarization: full context preserved across team lifespan

## Key Abstractions

**`Loomkin.AgentLoop` (ReAct Loop):**
- Purpose: Parameterized iteration logic decoupled from GenServer state
- Examples: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/agent_loop.ex`, `do_loop/3` function (lines 150-218)
- Pattern: Callback-driven — caller provides `on_event`, `check_permission`, `checkpoint` functions; loop emits events, checks permissions, pauses at checkpoints without hardcoding behavior

**`Jido.Action` (Tool Definition):**
- Purpose: Standardized tool interface with schema validation
- Examples: Every tool in `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/tools/` (e.g., `FileRead`, `Shell`, `TeamSpawn`)
- Pattern: `use Jido.Action`, define `schema/0` returning NimbleOptions validation, implement `run/2` returning `{:ok, result}` or `{:error, reason}`

**`Loomkin.Schemas.*` (Ecto Persistence):**
- Purpose: Type-safe database representation
- Examples: `Session`, `Message`, `DecisionNode`, `TeamTask`, `AuthToken`
- Pattern: Ecto schema with changesets, associations (has_many, belongs_to), custom field types (Ecto.Enum, binary_id)

**`Loomkin.Teams.Role` (Agent Configuration):**
- Purpose: Define agent behavior (lead/specialist/observer) with custom prompts, tool access, voting weight
- Location: `/Users/vinnymac/Sites/vinnymac/loomkin/lib/loomkin/teams/role.ex`
- Pattern: Role module registers itself with `role_registry`, provides system prompt fragment, determines tool availability

**Phoenix LiveView Component (UI):**
- Purpose: Real-time interactive UI with no JavaScript
- Examples: `workspace_live.ex` (main chat UI), `decision_graph_component.ex` (SVG DAG), `chat_component.ex` (message stream)
- Pattern: Phoenix.LiveView or Phoenix.LiveComponent, use `handle_info/2` for signal subscriptions, `send_update/2` for component state, `phx-*` bindings for user interaction

## Entry Points

**Web UI:**
- Location: `http://localhost:4200`
- Triggers: Browser request to `/` → `LoomkinWeb.Router` → `ProjectPickerLive` (project selection) → `WorkspaceLive` (chat)
- Responsibilities: Project selection, session creation, chat UI, live decision graph, team dashboard

**CLI (via GenServer):**
- Location: `Loomkin.Kin` (custom CLI interface, separate from this codebase's direct entry)
- Triggers: Custom CLI entry or `Loomkin.Session.start_link/1`
- Responsibilities: Parse CLI args, create session, send messages, display responses

**MCP Server (Model Context Protocol):**
- Location: `Loomkin.MCP.Server` (if enabled in config)
- Triggers: External editor tool requests
- Responsibilities: Expose Loomkin tools to external editors (LSP integration)

**MCP Client (Tool Consumer):**
- Location: `Loomkin.MCP.ClientSupervisor` in application supervision tree
- Triggers: Tool request needs external MCP resource
- Responsibilities: Connect to external MCP servers and delegate tool calls

**Application Start:**
- Location: `Loomkin.Application.start/2`
- Triggers: `mix run` or release binary execution
- Responsibilities: Initialize OTP supervision tree (Repo, Config, PubSub, SignalBus, Telemetry, SessionRegistry, Teams, Channels, optional MCP server, optional Phoenix endpoint)

## Error Handling

**Strategy:** Multi-layered with exponential backoff, budget tracking, and checkpoints.

**Patterns:**

1. **Rate Limiting / Budget:**
   - `Loomkin.AgentLoop` catches `{:rate_limited, provider}` and `{:budget_exceeded, scope}` exceptions
   - Retries with exponential backoff (2^attempt * 1000ms, max 3 attempts)
   - Emits `:rate_limited` event on each retry
   - If exhausted, returns `{:error, :rate_limited, messages}`
   - Example: lines 70-94 in `agent_loop.ex`

2. **Tool Execution Errors:**
   - `Jido.Exec.run/4` returns `{:ok, result}` or `{:error, reason}`
   - Tool result is stringified via `format_tool_result/1` (lines 654-666)
   - Errors prefixed with "Error: " and recorded in message list as tool response
   - Agent continues with next tool or gives final answer

3. **Permission Denied / Pending:**
   - Pre-tool hooks can return `:deny` (blocks tool) or `{:ask, reason}` (pauses for user confirmation)
   - Paused state returned as `{:pending_permission, pending_info, messages}` to owning process
   - Owning process handles user decision via `Loomkin.AgentLoop.resume/3`
   - Example: lines 397-462 in `agent_loop.ex`

4. **Max Iterations:**
   - Loop exits if `iteration >= max_iterations` (default 25)
   - Returns error message as assistant message so user sees it
   - Example: lines 134-148 in `agent_loop.ex`

5. **Checkpoint Pausing:**
   - After LLM response (`:post_llm`) or tool execution (`:post_tool`), checkpoint callback invoked
   - Callback can return `{:pause, reason}` to halt and return control
   - Used for interactive steering, supervision, or debugging
   - Example: lines 244-282 in `agent_loop.ex`

6. **GenServer Crashes:**
   - Session/Team.Agent crashes caught by supervisor
   - Supervisor restarts child (OTP default: exponential backoff)
   - In-flight messages lost (no persistence of partial state)
   - User sees error in UI, can retry

## Cross-Cutting Concerns

**Logging:**
- Framework: Elixir `:logger` module
- Approach: Structured logging with metadata (request_id, session_id, team_id)
- Configuration: `config :logger` in `config/config.exs` (console format with timestamp/level/message)
- Telemetry integration: `Loomkin.Telemetry` emits span events for LLM calls, tool execution, cost tracking

**Validation:**
- File paths: `Loomkin.Tool.safe_path!/2` rejects paths escaping project dir (symlink-aware)
- Tool arguments: `Jido.Action.Schema` validates against NimbleOptions schema
- Database: `Ecto.Changeset` validates Session, Message, Decision nodes before insert
- Permissions: `Loomkin.Permissions.HookRunner` pre-tool / post-tool hooks can deny/warn

**Authentication:**
- OAuth via `Assent` library for Google, OpenAI, Anthropic, etc.
- Tokens stored encrypted in `Loomkin.Schemas.AuthToken` via `Loomkin.Auth.TokenStore`
- PKCE flow managed by `Loomkin.Auth.OAuthServer` (prevents token leakage on redirects)
- Web session via Phoenix session (ETS-backed via `:ets.new(:loomkin_sessions, ...)`), see `Loomkin.Application` line 15

**Cost Tracking:**
- Per-session: `Loomkin.Schemas.Session` tracks `prompt_tokens`, `completion_tokens`, `cost_usd`
- Per-agent (team): `Loomkin.Schemas.AgentMetric` tracks cost, tokens, latency
- Per-provider pricing: `Loomkin.Teams.Pricing` module provides cost calculation
- Updated after each LLM call via `extract_usage/1` and persisted to DB

**Telemetry:**
- Framework: Erlang `:telemetry` library
- Metrics: `Loomkin.Telemetry.Metrics` defines counters (tool calls, errors), gauges (active sessions), histograms (latency)
- Spans: `Loomkin.Telemetry.span_llm_request/2`, `span_tool_execute/2` wrap execution and record duration
- Consumer: Metrics aggregated and exposed to dashboards (cost tracking, agent metrics)

**State Persistence:**
- Conversation history: `Loomkin.Schemas.Message` inserted after each response
- Session metadata: `Loomkin.Schemas.Session` updated with token counts, cost, status
- Decision graph: `DecisionNode`, `DecisionEdge` inserted by `AutoLogger`
- Context offload: Messages moved to `ContextKeeper` (in-memory, not DB)
- No auto-save of running state (agents killed = messages lost unless persisted to DB first)

---

*Architecture analysis: 2026-03-07*
