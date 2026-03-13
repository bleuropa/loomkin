# Codebase Structure

**Analysis Date:** 2026-03-07

## Directory Layout

```
loomkin/
├── lib/
│   ├── loomkin/                  # Core application logic
│   │   ├── agent_loop/           # ReAct iteration strategies
│   │   ├── auth/                 # OAuth token store, provider registry
│   │   ├── channels/             # Chat integrations (Telegram, Discord)
│   │   ├── decisions/            # Decision graph persistence and context building
│   │   ├── lsp/                  # LSP server for editor integration
│   │   ├── mcp/                  # Model Context Protocol (MCP server/client)
│   │   ├── permissions/          # Pre/post-tool hook system
│   │   ├── providers/            # OAuth provider implementations
│   │   ├── repo_intel/           # Codebase indexing and search
│   │   ├── schemas/              # Ecto schemas (database models)
│   │   ├── session/              # Session GenServer and context windowing
│   │   ├── signals/              # Signal type definitions
│   │   ├── teams/                # Team orchestration and agent management
│   │   ├── tools/                # 28+ executable tools (file ops, git, peer comms)
│   │   ├── application.ex        # OTP supervision tree
│   │   ├── agent_loop.ex         # Core ReAct loop (parameterized)
│   │   ├── config.ex             # Configuration loader
│   │   ├── llm.ex                # LLM streaming wrapper
│   │   ├── llm_retry.ex          # Exponential backoff retry logic
│   │   ├── models.ex             # Model metadata (context limits, pricing)
│   │   ├── repo.ex               # Ecto repository (database connection)
│   │   ├── telemetry.ex          # Telemetry metrics and spans
│   │   ├── tool.ex               # Shared tool helpers (path validation)
│   │   └── loomkin.ex            # Root module (version, docs)
│   │
│   └── loomkin_web/              # Phoenix web interface
│       ├── components/           # 25+ reusable LiveView components
│       ├── controllers/          # Auth, webhook handlers
│       ├── helpers/              # Template helpers
│       ├── live/                 # 6 main LiveView pages
│       ├── agent_colors.ex       # UI color scheme for agents
│       ├── endpoint.ex           # Phoenix endpoint configuration
│       ├── router.ex             # URL routing
│       └── loomkin_web.ex        # Macros for LiveView/Controller/Channel
│
├── test/
│   ├── loomkin/                  # Unit tests (mirrors lib/loomkin structure)
│   ├── loomkin_web/              # LiveView and controller tests
│   ├── support/                  # Test helpers and fixtures
│   └── test_helper.exs           # Test setup
│
├── priv/
│   ├── repo/
│   │   ├── migrations/           # Ecto database migrations
│   │   └── seeds.exs             # Development seed data
│   └── static/                   # Compiled assets (CSS, JS, images)
│
├── config/
│   ├── config.exs                # Base configuration (repo, phoenix, etc.)
│   ├── dev.exs                   # Development overrides
│   ├── prod.exs                  # Production overrides
│   ├── test.exs                  # Test overrides
│   └── runtime.exs               # Runtime (release) config
│
├── assets/
│   ├── js/                       # JavaScript/Tailwind CSS
│   ├── css/                      # Tailwind CSS input
│   ├── esbuild.js                # JS bundler config
│   └── tailwind.config.js        # Tailwind CSS config
│
├── docs/                         # Project documentation
├── rel/                          # Release overlay files
├── mix.exs                       # Mix project definition
├── mix.lock                      # Dependency lock file
├── Makefile                      # Development shortcuts
├── docker-compose.yml            # PostgreSQL + PgAdmin
├── .formatter.exs                # Elixir formatter config
├── .credo.exs                    # Code quality (Credo) config
├── .loomkin.toml.example         # Example user config
└── README.md                     # Project overview
```

## Directory Purposes

**`lib/loomkin/`:**
- Purpose: Core application logic
- Contains: Agent loop, session/team management, tools, decisions, auth, channels, LSP/MCP
- Key files: `application.ex` (supervision tree), `agent_loop.ex` (ReAct loop), `config.ex` (load config)

**`lib/loomkin/agent_loop/`:**
- Purpose: ReAct iteration strategy implementations
- Contains: `strategies/` directory with cot.ex, cod.ex, tot.ex, adaptive.ex (Chain-of-Thought, Chain-of-Density, Tree-of-Thought variants)
- Key files: `checkpoint.ex` (checkpoint data structure)

**`lib/loomkin/auth/`:**
- Purpose: OAuth and token management
- Contains: Token encryption, PKCE flow, provider registry
- Key files: `token_store.ex` (persistent encrypted tokens), `oauth_server.ex` (in-flight state), `provider.ex` (abstract), provider implementations

**`lib/loomkin/channels/`:**
- Purpose: Chat platform integrations
- Contains: `telegram/`, `discord/` subdirectories with webhook handlers
- Key files: Routes registered in `application.ex` under `Channels.Supervisor`

**`lib/loomkin/decisions/`:**
- Purpose: Decision graph persistence and reasoning memory
- Contains: DAG operations, auto-logging, context building, narrative generation
- Key files: `graph.ex` (insert/query nodes and edges), `auto_logger.ex` (listen to signals and log), `context_builder.ex` (inject context into prompts)

**`lib/loomkin/lsp/`:**
- Purpose: Language Server Protocol integration
- Contains: LSP server for editor (VS Code, Neovim, etc.), diagnostics handling
- Key files: `supervisor.ex` (manages LSP instances per project)

**`lib/loomkin/mcp/`:**
- Purpose: Model Context Protocol (Claude's tool standard)
- Contains: MCP server (expose Loomkin tools to editors), MCP client (consume external tools)
- Key files: `server.ex` (MCP server), `client_supervisor.ex` (MCP client management)

**`lib/loomkin/permissions/`:**
- Purpose: Tool execution permission hooks
- Contains: Pre-tool hooks (deny/ask), post-tool hooks (rollback/warn)
- Key files: `hooks/` directory with user-defined hook modules

**`lib/loomkin/providers/`:**
- Purpose: OAuth provider integrations (separate from auth/)
- Contains: Google, OpenAI, Anthropic provider implementations
- Key files: Each provider registers with `ReqLLM` via `register!/0`

**`lib/loomkin/repo_intel/`:**
- Purpose: Codebase indexing and search
- Contains: Tree-sitter symbol extraction, file watcher, repo map generation
- Key files: `index.ex` (in-memory symbol cache), `watcher.ex` (file change listener), `repo_map.ex` (generate repo structure summary)

**`lib/loomkin/schemas/`:**
- Purpose: Ecto database models
- Contains: 12 schemas with changesets and associations
- Key files: `session.ex`, `message.ex`, `decision_node.ex`, `decision_edge.ex`, `team_task.ex`, `auth_token.ex`, etc.

**`lib/loomkin/session/`:**
- Purpose: Single-user solo session management
- Contains: Session GenServer, context windowing, session composition, persistence
- Key files: `session.ex` (main GenServer), `context_window.ex` (token budgeting), `architect.ex` (session state assembly), `manager.ex` (session PID registry)

**`lib/loomkin/signals/`:**
- Purpose: Typed event definitions for Jido Signal Bus
- Contains: Signal module definitions (session signals, team signals, etc.)
- Key files: `session.ex`, `team.ex` (define signal structure with `use Jido.Signal`)

**`lib/loomkin/teams/`:**
- Purpose: Multi-agent team orchestration
- Contains: Agent GenServer, team supervisor, role definitions, consensus, cost tracking, context overflow, peer comms
- Key files: `agent.ex` (per-agent GenServer), `supervisor.ex` (spawn/destroy teams), `role.ex` (agent configuration), `context_keeper.ex` (overflow handler), `comms.ex` (peer messaging)

**`lib/loomkin/tools/`:**
- Purpose: 28+ executable LLM-callable tools
- Contains: File operations (read/write/edit), git commands, shell execution, decision queries, peer tools, team management
- Key files: `registry.ex` (all available tools), individual tool modules (`file_read.ex`, `shell.ex`, `team_spawn.ex`, etc.)

**`lib/loomkin_web/`:**
- Purpose: Phoenix LiveView web interface
- Contains: LiveView pages, reusable components, authentication controller, webhook handler
- Key files: `router.ex` (URL routes), `endpoint.ex` (server config), `workspace_live.ex` (main chat UI)

**`lib/loomkin_web/components/`:**
- Purpose: Reusable Phoenix LiveView components
- Contains: 25+ components for chat, decision graph, team dashboard, file explorer, etc.
- Key files: `chat_component.ex` (message display), `decision_graph_component.ex` (SVG DAG), `team_dashboard_component.ex`, `tool_calls_component.ex`

**`lib/loomkin_web/live/`:**
- Purpose: Main LiveView pages (full-page components)
- Contains: 6 pages for project selection, workspace, dashboard
- Key files: `workspace_live.ex` (main chat interface), `project_picker_live.ex` (project selection), `cost_dashboard_live.ex` (analytics)

**`test/`:**
- Purpose: Test suite (925+ tests)
- Contains: Unit tests for tools, config, decisions, auth, teams, schemas
- Key files: Mirrors `lib/` structure with `_test.exs` suffix (e.g., `test/loomkin/tools/file_read_test.exs`)

**`test/support/`:**
- Purpose: Shared test helpers
- Contains: Test factories, mocks, fixtures
- Key files: `test_helper.exs` (setup), helper modules for specific domains

**`config/`:**
- Purpose: Application configuration
- Contains: Environment-specific overrides (dev/test/prod)
- Key files: `config.exs` (base), `runtime.exs` (release-time config from env vars)

**`priv/repo/migrations/`:**
- Purpose: Database schema
- Contains: Numbered migrations for tables, indexes, constraints
- Key files: Schema evolution tracked in migration sequence

**`assets/`:**
- Purpose: Frontend build (CSS, JS)
- Contains: Tailwind CSS input, esbuild bundler config
- Key files: `js/app.js` (entry point), `tailwind.config.js` (styles), `css/app.css`

## Key File Locations

**Entry Points:**

- **Web:** `lib/loomkin_web/router.ex` (URL routing)
- **CLI/Session:** `lib/loomkin/application.ex` (OTP startup)
- **LLM Integration:** `lib/loomkin/llm.ex` (streaming wrapper)
- **Decision Graph:** `lib/loomkin/decisions/graph.ex` (DAG operations)

**Configuration:**

- **App config:** `config/config.exs`, `config/runtime.exs`
- **Database:** `lib/loomkin/repo.ex`
- **Tool registry:** `lib/loomkin/tools/registry.ex`
- **Auth providers:** `lib/loomkin/auth/provider_registry.ex`

**Core Logic:**

- **ReAct loop:** `lib/loomkin/agent_loop.ex` (main iteration logic, 810 lines)
- **Session state:** `lib/loomkin/session/session.ex` (GenServer, 400+ lines)
- **Team orchestration:** `lib/loomkin/teams/agent.ex` (per-agent, 600+ lines), `teams/supervisor.ex`
- **Context windowing:** `lib/loomkin/session/context_window.ex` (token budgeting, 300+ lines)

**Testing:**

- **Test setup:** `test/test_helper.exs`
- **Tool tests:** `test/loomkin/tools/*_test.exs` (28 test files)
- **Schema tests:** `test/loomkin/schemas/` (database model tests)
- **Integration tests:** `test/loomkin/auth/*_test.exs`, `test/loomkin/teams/*_test.exs`

**Web Interface:**

- **Main workspace:** `lib/loomkin_web/live/workspace_live.ex` (chat UI, handles messages/streams)
- **Auth controller:** `lib/loomkin_web/controllers/auth_controller.ex` (OAuth flow)
- **Chat component:** `lib/loomkin_web/components/chat_component.ex` (message rendering)
- **Decision graph UI:** `lib/loomkin_web/components/decision_graph_component.ex` (SVG DAG visualization)

## Naming Conventions

**Files:**

- Modules: `snake_case.ex` (e.g., `file_read.ex`, `team_spawn.ex`, `context_window.ex`)
- Tests: `*_test.exs` (e.g., `file_read_test.exs`)
- Migrations: `YYYYMMDDHHMMSS_descriptor.exs` (Ecto standard)

**Directories:**

- Feature domains: plural noun (e.g., `tools/`, `teams/`, `schemas/`, `channels/`)
- Internal structure: descriptive (e.g., `agent_loop/strategies/`, `teams/role.ex`)

**Modules:**

- Root: `Loomkin` (application), `LoomkinWeb` (web)
- Tools: `Loomkin.Tools.*` (e.g., `Loomkin.Tools.FileRead`, `Loomkin.Tools.TeamSpawn`)
- Schemas: `Loomkin.Schemas.*` (e.g., `Loomkin.Schemas.Session`, `Loomkin.Schemas.Message`)
- Teams: `Loomkin.Teams.*` (e.g., `Loomkin.Teams.Agent`, `Loomkin.Teams.Supervisor`)
- Web: `LoomkinWeb.*` (e.g., `LoomkinWeb.WorkspaceLive`, `LoomkinWeb.ChatComponent`)

**Functions:**

- Private: Single underscore prefix (e.g., `_build_messages/1` in tests, actual privates implicit via `defp`)
- Public: No prefix (e.g., `send_message/2`, `get_history/1`)
- Callbacks: `on_*` or `handle_*` (e.g., `on_event`, `handle_info`)

## Where to Add New Code

**New Tool (e.g., "compile_and_test"):**

1. Create: `lib/loomkin/tools/compile_and_test.ex`
   - Use `use Jido.Action` with schema validation
   - Implement `run(args, context)` returning `{:ok, result}`
   - Add to `@solo_tools` or `@peer_tools` in `lib/loomkin/tools/registry.ex`

2. Test: `test/loomkin/tools/compile_and_test_test.exs`
   - Use test mocks/fixtures from `test/support/`
   - Follow pattern: setup test data, call tool, assert result

**New Schema (e.g., "code_snippet"):**

1. Create: `lib/loomkin/schemas/code_snippet.ex`
   - Define Ecto schema with fields and associations
   - Write changeset with validations

2. Migrate: `priv/repo/migrations/YYYYMMDDHHMMSS_create_code_snippets.exs`
   - Run `mix ecto.gen.migration create_code_snippets`
   - Add table, constraints, indexes

3. Test: `test/loomkin/schemas/code_snippet_test.exs`
   - Test changeset validations

**New LiveView Page (e.g., "analytics_live"):**

1. Create: `lib/loomkin_web/live/analytics_live.ex`
   - Use `use LoomkinWeb, :live_view`
   - Implement `mount/3`, `handle_event/3`, `handle_info/2`
   - Render with `~H"""` sigil

2. Add route: `lib/loomkin_web/router.ex`
   - Add `live "/analytics", AnalyticsLive, :index`

3. Test: `test/loomkin_web/live/analytics_live_test.exs`
   - Use `Phoenix.LiveViewTest` (render, assert, click, etc.)

**New Component (e.g., "chart_component"):**

1. Create: `lib/loomkin_web/components/chart_component.ex`
   - Use `use LoomkinWeb, :live_component`
   - Define slot `attr`s, `prop` slots, render function
   - Implement `update/2` if stateful

2. Use from LiveView:
   - `<.chart_component id="chart-1" title="Costs" />`

3. Test: Include in parent LiveView test or write component-specific test

**New Permissions Hook (e.g., "deny_shell_as_root"):**

1. Create: `lib/loomkin/permissions/hooks/deny_shell_as_root.ex`
   - Implement `check_pre_tool/2` → `:allow` | `:deny` | `{:ask, reason}`
   - Or `check_post_tool/3` → `:ok` | `{:rollback, reason}`

2. Load in project `.loomkin.toml`:
   ```toml
   [permissions]
   pre_hooks = ["Loomkin.Permissions.Hooks.DenyShellAsRoot"]
   ```

3. Test: `test/loomkin/permissions/hooks/deny_shell_as_root_test.exs`

## Special Directories

**`lib/loomkin/agent_loop/strategies/`:**
- Purpose: Alternate reasoning strategies beyond standard ReAct
- Generated: No (hand-written)
- Committed: Yes
- Files: `cot.ex` (Chain-of-Thought), `cod.ex` (Chain-of-Density), `tot.ex` (Tree-of-Thought), `adaptive.ex` (switch based on task)

**`test/support/`:**
- Purpose: Shared test utilities
- Generated: No (hand-written fixtures)
- Committed: Yes
- Usage: Imported by test modules, provides factories, mocks, helpers

**`priv/static/`:**
- Purpose: Compiled frontend assets (CSS, JS, images)
- Generated: Yes (by esbuild and tailwind during `mix assets.build`)
- Committed: No (in .gitignore)
- Served: From `http://localhost:4200/assets/` by Phoenix

**`.loomkin/`:**
- Purpose: Runtime cache (tree-sitter index, LSP artifacts)
- Generated: Yes (auto-created at startup)
- Committed: No (in .gitignore)
- Contents: Symbol cache, LSP temp files

**`.claude/`:**
- Purpose: Claude AI context snapshots (for GSD commands)
- Generated: Yes (by orchestrator commands)
- Committed: No (in .gitignore)
- Contents: Codebase analysis documents (ARCHITECTURE.md, etc.)

**`_build/`:**
- Purpose: Compiled Erlang/Elixir bytecode
- Generated: Yes (by `mix compile`)
- Committed: No (in .gitignore)

**`deps/`:**
- Purpose: Downloaded dependencies
- Generated: Yes (by `mix deps.get`)
- Committed: No (in .gitignore)

---

*Structure analysis: 2026-03-07*
