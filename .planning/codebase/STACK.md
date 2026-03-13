# Technology Stack

**Analysis Date:** 2026-03-07

## Languages

**Primary:**
- Elixir 1.18.4 - Backend application logic, CLI, agents, tools
- JavaScript - Asset building and processing (via esbuild)
- CSS - Styling with Tailwind

**Secondary:**
- HTML (embedded in HEEX templates for Phoenix LiveView)
- Markdown - Documentation and parsed content processing

## Runtime

**Environment:**
- Erlang/OTP 27 - Execution environment for Elixir
- Node.js 22 - Asset building (esbuild, Tailwind)

**Package Manager:**
- Mix (Hex) - Primary Elixir package manager
- `mix.lock` - Lock file present for Elixir dependencies
- npm - JavaScript dependency management for assets
- `package-lock.json` - Lock file present (in `assets/`)

## Frameworks

**Core:**
- Phoenix 1.7.x - Web framework, LiveView, real-time channels
- Phoenix LiveView 1.0 - Interactive real-time UI components
- Ecto 3.12 - Database abstraction and ORM layer
- Phoenix Ecto 4.6 - Ecto integration with Phoenix

**LLM & AI:**
- ReqLLM 1.6 - Unified LLM client supporting 16+ providers
- LLMDB - Model catalog and provider database
- Jido 2.0 - AI agent framework for action composition
- Jido Action 2.0 - Action definition and execution
- Jido Signal 2.0 - Event-driven signal bus
- Jido AI - AI-specific action helpers
- Jido MCP - Model Context Protocol integration

**Build/Dev:**
- esbuild 0.8 - JavaScript bundler (runtime in dev)
- Tailwind 0.2 - CSS framework and CLI tool (runtime in dev)
- Phoenix Live Reload 1.5 - Hot reload in development
- Bandit 1.6 - HTTP server adapter

**Testing:**
- ExUnit - Built-in Elixir test framework
- Mox 1.0 - Mocking library
- Floki 0.37 - HTML parsing for LiveView tests
- LazyHTML >=0.1.0 - Lazy HTML evaluation

**Development Tools:**
- Credo 1.7 - Code analysis and style checker
- Tidewave 0.5 - Development utilities
- Mix format - Code formatter (built-in)

## Key Dependencies

**Critical:**
- Postgrex - PostgreSQL database driver (`>= 0.0.0`)
- Plug Cowboy 2.7 - Cowboy HTTP server adapter
- Jason 1.4 - JSON encoding/decoding

**Infrastructure:**
- DNS Cluster 0.1 - Distributed Erlang cluster support
- Telemetry 1.3 - Metrics collection
- Phoenix HTML 4.2 - HTML generation utilities
- Phoenix Live Dashboard 0.8 - Development monitoring dashboard

**Configuration & Processing:**
- TOML (custom via `vinnymac/toml-elixir`) - Config file parsing
- YAML Elixir 2.12 - YAML parsing
- Diff Match Patch 0.3 - Diff/patch operations for code editing
- Mdex 0.6 - Markdown parsing and processing

**CLI & Git:**
- Owl 0.13 - Terminal UI utilities
- Git CLI 0.3 - Git operations wrapper
- File System 1.1 - File system watcher

**Authentication:**
- Assent 0.3.1 - OAuth provider abstraction layer
- Plug 2.x (via dependencies) - Session management with encrypted cookies

**Channel Adapters:**
- Telegex (custom via `vinnymac/telegex`) - Telegram Bot API client
- Nostrum 0.10 - Discord.js-like Elixir client

**Binary Packaging:**
- Burrito 1.0 - Cross-platform binary release packaging
- Targets: macOS (ARM64, x86_64), Linux (x86_64, ARM64)

**Custom Dependencies:**
- SchedEx (custom via `vinnymac/SchedEx`) - Scheduling utilities
- Abacus (custom via `vinnymac/abacus`) - Mathematical expressions

## Configuration

**Environment Variables:**

### Database
- `DATABASE_URL` - Connection string (required in production; fallback to `config.exs` in dev)
- `POOL_SIZE` - PostgreSQL connection pool size (default: 10)
- `DB_PORT` - Override PostgreSQL port (default: 5488 for Docker, 5432 system)

### Web Server
- `PHX_HOST` - Hostname for production endpoint (default: localhost)
- `PORT` - HTTP server port (default: 4200)
- `SECRET_KEY_BASE` - Session encryption key (generated from home directory hash if not set)

### LLM Providers (API Keys)
- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_API_KEY` - OpenAI API key
- `GOOGLE_API_KEY` - Google API key
- `ZAI_API_KEY` - Z.AI API key
- `XAI_API_KEY` - xAI API key
- `GROQ_API_KEY` - Groq API key
- `DEEPSEEK_API_KEY` - DeepSeek API key
- `OPENROUTER_API_KEY` - OpenRouter API key
- `MISTRAL_API_KEY` - Mistral API key
- `CEREBRAS_API_KEY` - Cerebras API key
- `TOGETHER_API_KEY` - Together AI API key
- `FIREWORKS_API_KEY` - Fireworks AI API key
- `COHERE_API_KEY` - Cohere API key
- `PERPLEXITY_API_KEY` - Perplexity API key
- `NVIDIA_API_KEY` - NVIDIA API key
- `AZURE_API_KEY` - Azure API key

### Application
- `LOOMKIN_MODEL` - Default LLM model override (default: "zai:glm-5")
- `MIX_TEST_PARTITION` - Test database partition suffix (for parallel tests)

**Build Configuration:**
- `config/config.exs` - Base configuration for all environments
- `config/dev.exs` - Development-specific (hot reload, debug mode)
- `config/test.exs` - Test-specific (in-memory strategies, warnings disabled)
- `config/prod.exs` - Production stub (real config in `config/runtime.exs`)
- `config/runtime.exs` - Runtime config (executed when app starts; reads env vars)

**Asset Configuration:**
- `esbuild` config: JavaScript bundler for `/assets/js/app.js` → `priv/static/assets/`
- `tailwind` config: CSS processing from `/assets/css/app.css` → `priv/static/assets/app.css`
- `assets/` - Node.js 22 environment with highlight.js dependency

## Platform Requirements

**Development:**
- Erlang 27
- Elixir 1.18.4
- Node.js 22
- PostgreSQL (local or Docker on port 5488)
- Lefthook 2.1.2 (git hooks for pre-commit validation)

**Production:**
- Deployment via Burrito-generated binary (self-contained, no runtime dependencies)
- Targets: macOS (ARM64, x86_64), Linux (x86_64, ARM64)
- PostgreSQL database (connection via `DATABASE_URL`)
- Environment variables for secrets and API keys

**Release Configuration:**
- Release name: `loomkin`
- Burrito wrapping: Cross-platform binary generation
- OTP Release version: `0.1.0`

## Service Integrations

**Web Server:**
- Bandit (HTTP adapter) with Plug Cowboy fallback
- Socket support: WebSocket + long-polling for LiveView
- Static asset serving: `priv/static/` with gzip support

**Dashboard & Monitoring:**
- Phoenix Live Dashboard 0.8 (development-only at `/dev/dashboard`)
- Request logging with Telemetry
- Tidewave (development enhancements)

**Code Quality:**
- Mix format - Code formatting
- Credo - Linting (style and complexity checks)
- Live reload - Hot code reloading in development

---

*Stack analysis: 2026-03-07*
