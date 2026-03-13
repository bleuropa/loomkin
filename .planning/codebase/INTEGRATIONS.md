# External Integrations

**Analysis Date:** 2026-03-07

## APIs & External Services

**LLM Providers (16+):**
- Anthropic (Claude) - OAuth + API key supported
  - SDK: ReqLLM (via req_llm 1.6)
  - OAuth provider: `Loomkin.Providers.AnthropicOAuth`
  - Auth module: `Loomkin.Auth.Providers.Anthropic`
  - Flow type: Paste-back token exchange
  - Env var: `ANTHROPIC_API_KEY`

- Google (Gemini, PaLM) - OAuth + API key supported
  - SDK: ReqLLM
  - OAuth provider: `Loomkin.Providers.GoogleOAuth`
  - Auth module: `Loomkin.Auth.Providers.Google`
  - Flow type: OAuth redirect
  - Env var: `GOOGLE_API_KEY`

- OpenAI (GPT-4, GPT-3.5) - OAuth + API key supported
  - SDK: ReqLLM
  - OAuth provider: `Loomkin.Providers.OpenAIOAuth`
  - Auth module: `Loomkin.Auth.Providers.OpenAI`
  - Flow type: OAuth redirect
  - Env var: `OPENAI_API_KEY`

- Z.AI, xAI, Groq, DeepSeek, OpenRouter, Mistral, Cerebras, Together AI, Fireworks AI, Cohere, Perplexity, NVIDIA, Azure - API key only
  - SDK: ReqLLM
  - Env vars: See STACK.md environment variables section

**Model Discovery:**
- LLMDB - Model catalog service
  - Client: `Loomkin.Models` module queries LLMDB
  - Purpose: List available chat-capable models from each provider
  - Location: `lib/loomkin/models.ex`

**ReqLLM Configuration:**
- Location: `config/config.exs` lines 60-74
- Streaming timeouts: 120 seconds (extended for long LLM responses)
- HTTP pool: 1 default pool, 8 concurrent connections
- Transport timeout: 120 seconds per connection

## Data Storage

**Databases:**
- PostgreSQL (primary)
  - Connection: `Loomkin.Repo` (Ecto adapter)
  - Env var: `DATABASE_URL` (production) or local config
  - Default port: 5488 (Docker), 5432 (system)
  - Connection pool: 10 connections default, configurable via `POOL_SIZE`
  - Client: Postgrex driver via Ecto

**Core Schemas:**
- `Loomkin.Schemas.Session` - User sessions with team/fast model config
- `Loomkin.Schemas.DecisionNode` - Decision graph nodes with agent metadata
- `Loomkin.Schemas.DecisionEdge` - Edges in decision graph
- `Loomkin.Schemas.ContextKeeper` - Persistent context storage
- `Loomkin.Schemas.AuthToken` - Encrypted OAuth tokens (see Authentication section)
- `Loomkin.Schemas.Message` - Channel messages
- `Loomkin.Schemas.ChannelBinding` - Discord/Telegram channel associations
- `Loomkin.Schemas.KinAgent` - AI agent instances
- `Loomkin.Schemas.TeamTask` - Task management for agent teams
- `Loomkin.Schemas.TeamTaskDep` - Task dependencies
- `Loomkin.Schemas.PermissionGrant` - Channel-level permissions
- `Loomkin.Schemas.PermissionAuditLog` - Permission change audit trail
- `Loomkin.Schemas.AgentMetric` - Performance metrics for agents

**File Storage:**
- Local filesystem only (no cloud storage integration)
- Static assets: `priv/static/assets/` (compiled CSS/JS)
- Temporary files: System temp directory (for git operations, LSP)

**Caching:**
- ETS tables (in-memory):
  - `:loomkin_sessions` - Session state
  - `:loomkin_auth_tokens` - Decrypted OAuth tokens (fast lookup path)
- Phoenix PubSub - Event broadcasting across cluster
- Jido Signal Bus - Typed event routing (`lib/loomkin/signals.ex`)

## Authentication & Identity

**OAuth Providers:**
- Location: `lib/loomkin/auth/`
- Central registry: `Loomkin.Auth.ProviderRegistry` (single source of truth)
- Three OAuth-capable providers: Anthropic, Google, OpenAI
- Token persistence: `Loomkin.Auth.TokenStore`
  - Encryption: Plug.Crypto with `secret_key_base`
  - Automatic refresh: 5 minutes before expiry
  - Storage: Encrypted in PostgreSQL + plaintext ETS cache
  - Lifecycle: `store_tokens/2` → `get_access_token/1` → auto-refresh → `revoke_tokens/1`

**Token Management:**
- Location: `lib/loomkin/auth/token_store.ex`
- Encryption scheme: MessageEncryptor with 64-byte key (32 enc + 32 sign)
- Expiration handling: Checks token expiry on every access
- Refresh retry: 3 attempts with exponential backoff (15s, 60s, 240s)
- Broadcast events: Via Jido Signal Bus
  - `AuthConnected` - After token store
  - `AuthRefreshed` - After successful refresh
  - `AuthDisconnected` - After revocation
  - `AuthRefreshFailed` - After failed refresh

**Session Management:**
- Type: Encrypted HTTP cookies (Plug.Session)
- Cookie: `_loom_key`
- Signing salt: `"loom_sign"`
- Encryption salt: `"loom_encrypt"`
- Store: ETS table (`:loomkin_sessions`)
- LiveView signing salt: `"loomkin_lv_salt"`

**LLM Request Auth:**
- Location: `lib/loomkin/llm.ex`
- Strategy: Transparent OAuth upgrade
  - If OAuth token available: Route to OAuth provider module (e.g., `AnthropicOAuth`)
  - If no OAuth token: Fall through to ReqLLM with API key
- Check: `Loomkin.LLM.oauth_active?/1` returns boolean for provider
- Providers map: `Loomkin.LLM.oauth_providers/0`

## Monitoring & Observability

**Error Tracking:**
- None detected (no Sentry, Bugsnag, etc.)

**Logs:**
- Logger: Built-in Elixir `:logger`
- Format: `$time $metadata[$level] $message\n`
- Metadata: `[:request_id]`
- Log levels:
  - Dev: `:debug`
  - Test: `:warning`
  - Prod: Configurable
- Transitive dep logging: anubis_mcp silenced (custom config)

**Metrics & Telemetry:**
- Telemetry 1.3 - Metrics collection framework
- Location: `lib/loomkin/telemetry.ex`
- Event prefix: `[:phoenix, :endpoint]`
- Phoenix Live Dashboard 0.8 - Development-only UI at `/dev/dashboard`
- Metrics: Agent performance (`AgentMetric` schema)

## CI/CD & Deployment

**Hosting:**
- Binary release: Burrito cross-platform executables
- Supported targets: macOS (ARM64, x86_64), Linux (x86_64, ARM64)
- Release step: `[:assemble, &Burrito.wrap/1]`
- Cookie: `loomkin_0.1.0`
- Application: `runtime_tools` set to `:permanent`

**CI Pipeline:**
- Git hooks: Lefthook 2.1.2
- Pre-commit: `mix precommit` (run before pushing)
- Build: `mix ecto.create --quiet && mix ecto.migrate --quiet && mix test`
- Asset build: `esbuild` + `tailwind` + `phx.digest`
- Code quality: `mix format`, `mix credo`

**Deployment Process:**
- Runtime migration: Auto-migrate on release startup (if release mode detected)
- Configuration: All runtime config via `config/runtime.exs` (reads env vars)
- Database setup: Ecto creates database and runs migrations on first boot

## Environment Configuration

**Required env vars (production):**
- `DATABASE_URL` - PostgreSQL connection string (must be set, raises on missing)
- `SECRET_KEY_BASE` - Fallback: SHA256 hash of home directory + "loomkin_secret_salt"

**Optional env vars:**
- `PHX_HOST` - HTTP host (default: localhost)
- `PORT` - HTTP port (default: 4200)
- `LOOMKIN_MODEL` - Default LLM model (default: zai:glm-5)
- `POOL_SIZE` - DB connection pool (default: 10)
- `MIX_TEST_PARTITION` - Test DB partition for parallel runs

**Secrets location:**
- OAuth tokens: Encrypted in PostgreSQL (AuthToken schema), decrypted plaintext in ETS cache
- API keys: Environment variables only (not persisted to disk)
- Session cookie key: Derived from `secret_key_base`

## Webhooks & Callbacks

**Incoming Webhooks:**
- **Telegram**: `POST /api/webhooks/telegram`
  - Handler: `Loomkin.Channels.Telegram.Webhook`
  - Location: `lib/loomkin/channels/telegram/webhook.ex`
  - Verification: Optional `X-Telegram-Bot-API-Secret-Token` header
  - Dispatch: Routes to `Loomkin.Channels.Router`
  - Mode: Webhook (polling also supported via `Loomkin.Channels.Telegram.Poller`)

**OAuth Callbacks:**
- **Anthropic**: `GET /auth/anthropic/callback` (paste-back token exchange)
- **Google**: `GET /auth/google/callback` (redirect flow)
- **OpenAI**: `GET /auth/openai/callback` (redirect flow)
- Handler: `LoomkinWeb.AuthController`
- Routes: `lib/loomkin_web/router.ex` lines 18-26

**Outgoing Webhooks:**
- None detected

## Channel Integrations

**Telegram:**
- Location: `lib/loomkin/channels/telegram/`
- Client: Telegex (custom fork via `vinnymac/telegex`)
- Webhook handler: `Loomkin.Channels.Telegram.Webhook`
- Poller: `Loomkin.Channels.Telegram.Poller` (alternative to webhook)
- Adapter: `Loomkin.Channels.Telegram.Adapter`
- Message formatting: `Loomkin.Channels.Telegram.Formatter`
- Token: Configured via env var (not exposed in codebase)

**Discord:**
- Location: `lib/loomkin/channels/discord/`
- Client: Nostrum 0.10 (Discord.js-like Elixir library)
- Consumer: `Loomkin.Channels.Discord.Consumer` (event handler)
- Adapter: `Loomkin.Channels.Discord.Adapter`
- Message formatting: `Loomkin.Channels.Discord.Formatter`
- Token: Configured via env var (not exposed in codebase)
- Permissions: `Loomkin.Channels.Permission.Registry`
- Audit logging: `Loomkin.Channels.AuditLog`

**Channel Management:**
- Location: `lib/loomkin/channels/supervisor.ex`
- Bindings: Channel ↔ Discord/Telegram associations (`ChannelBinding` schema)
- Routing: `Loomkin.Channels.Router` dispatches messages to handlers
- Message type: `Loomkin.Channels.Message` (unified abstraction)

## MCP (Model Context Protocol)

**MCP Server:**
- Location: `lib/loomkin/mcp/server.ex`
- Purpose: Expose Loomkin tools to external MCP clients
- Enabled: Conditional startup based on configuration
- Child specs: `Loomkin.MCP.Server.child_specs()`

**MCP Clients:**
- Location: `lib/loomkin/mcp/client_supervisor.ex`
- Purpose: Connect to external MCP servers
- Management: Dynamic supervisor for MCP client connections
- Start trigger: React to `:config_loaded` signal

**LSP (Language Server Protocol):**
- Location: `lib/loomkin/lsp/supervisor.ex`
- Purpose: Code intelligence integration
- Trigger: Reacts to `:config_loaded` signal
- Symbol cache: `Loomkin.RepoIntel.TreeSitter.init_cache()`

## Repository Intelligence

**Code Indexing:**
- Location: `lib/loomkin/repo_intel/index.ex`
- Purpose: Index project files and code symbols
- File watching: `Loomkin.RepoIntel.Watcher` monitors for file changes
- Tree-sitter: Symbol extraction via tree-sitter (initialized at startup)

**Capabilities:**
- Directory listing: `Loomkin.Tools.DirectoryList`
- File operations: Read/write/edit/search
- Git integration: `Loomkin.Tools.Git` (via git_cli package)
- LSP diagnostics: `Loomkin.Tools.LspDiagnostics`

---

*Integration audit: 2026-03-07*
