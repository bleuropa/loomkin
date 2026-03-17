<p align="center">
  <img src="assets/loomkin-banner.jpg" alt="Loomkin — The Weaver Owl" width="600">
</p>

# Loomkin

[![CI](https://github.com/bleuropa/loomkin/actions/workflows/ci.yml/badge.svg)](https://github.com/bleuropa/loomkin/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Discord](https://img.shields.io/discord/1465498806698119317?color=5865F2&logo=discord&logoColor=white&label=Discord)](https://discord.gg/WUVneqArVD)
[![Elixir](https://img.shields.io/badge/Elixir-1.20+-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org)
[![Last Commit](https://img.shields.io/github/last-commit/bleuropa/loomkin)](https://github.com/bleuropa/loomkin/commits/main)

**What if AI agents could form teams as fluidly as humans?**

Spawn specialists in milliseconds. Share discoveries in real-time. Review each other's work. Debate approaches and vote on decisions. Heal themselves when things break. Verify their own output before moving on. Remember everything across sessions — not just what happened, but *why*.

Watch it all unfold from a live mission control UI. Built on Erlang/OTP.

- **Decision graph** — persistent reasoning memory that survives across sessions (not just chat history)
- **Context mesh** — overflow is offloaded to Keeper processes with staleness tracking and failure memory, never summarized away. 228K+ tokens preserved vs 128K with zero loss
- **Agent teams** — OTP-native, <500ms spawn, microsecond coordination. 10 cheap agents for ~$0.25 vs ~$4.50 single-Opus
- **Conversation agents** — any agent can spawn a brainstorm, design review, or red team exercise. Deliberation as a service
- **Self-healing teams** — error classification, automatic diagnosis and repair via ephemeral agents, no human intervention needed
- **Verification loops** — autonomous write-test-diagnose-fix cycles with upstream verifiers that check output before dependents proceed
- **Workspaces** — persistent layer above sessions. Teams, tasks, and progress survive tab closes and reconnects
- **LiveView web UI** — 39 components, zero handwritten JavaScript. Mission control with agent cards, comms feed, decision graph, context library, settings, permissions dashboard
- **58 built-in tools**, 16 LLM providers, 665+ models via [req_llm](https://github.com/agentjido/req_llm), plus Ollama for local LLMs
- **Skill system** — agents discover and load skills on demand from disk, in-app authoring, or community snippets
- **Hot code reloading** — update tools, providers, and prompts without restarting sessions or losing state

[loomkin.dev](https://loomkin.dev) | 305 source files, ~73K LOC, 2,600+ tests

<p align="center">
  <img src="assets/loomkin-example.jpg" alt="Loomkin example session — fixing a failing test" width="700">
</p>

---

## How Loomkin is Different

| | Traditional AI Assistants | Loomkin |
|---|---|---|
| **Default experience** | Single agent, teams opt-in | Teams-first: every session is a team of 1+ that auto-scales |
| **Memory** | Conversation history, maybe embeddings | Persistent decision graph — goals, tradeoffs, rejected approaches survive across sessions |
| **Context** | Summarized away as it grows (lossy) | Context Mesh: offloaded to Keeper processes with staleness tracking, zero loss, 228K+ tokens preserved |
| **Agent spawn** | 20-30 seconds | <500ms (`GenServer.start_link`) |
| **Inter-agent messaging** | JSON files on disk, polled | In-memory PubSub, microsecond latency, cross-team discovery |
| **Concurrent file edits** | Overwrite risk | Region-level locking with intent broadcasting |
| **Task decomposition** | Lead plans upfront, frozen | Living plans: agents create tasks, negotiate assignments, propose revisions, re-plan as they learn |
| **Peer review** | None | Native protocol — review gates, pair programming, structured handoffs |
| **Agent concurrency** | 3-5 practical limit | 100+ lightweight processes per node |
| **Model mixing** | Single model for all agents | Per-agent selection — cheap grunts + expensive judges (18x cost savings) |
| **Error recovery** | Crash = lost session | Self-healing: error classification, ephemeral diagnostician + fixer agents, OTP supervision |
| **Verification** | Manual testing | Autonomous verify loops — write, test, diagnose, fix, re-test. Upstream verifiers gate dependents |
| **Deliberation** | None | Conversation agents — spawn brainstorms, design reviews, red teams on demand |
| **Web UI** | Terminal only, or separate web app | LiveView mission control — agent cards, comms feed, decision graph, context library, permissions. Zero JS |
| **Decision persistence** | None | PostgreSQL DAG with 7 node types, typed edges, confidence scores, pulse reports |
| **Session persistence** | None | Workspaces persist teams and tasks across tab closes and reconnects |
| **MCP** | Client or server | Both — expose tools to editors AND consume external tools |
| **Hot reload** | Restart required | Update tools, providers, prompts while agents are running |

[Why Elixir and the BEAM?](docs/why-elixir.md)

---

## Getting Started

### Prerequisites

- Elixir 1.20+ (with Erlang/OTP 28+) — versions pinned in `.mise.toml`
- Docker (we recommend [OrbStack](https://orbstack.dev) on macOS — fast, lightweight Docker runtime)
- Node.js 22 — for asset compilation
- An API key for at least one LLM provider (Anthropic, OpenAI, Google, etc.)

> **No Docker?** If you prefer system-installed Postgres, set `DB_PORT=5432` (or your custom port) in your environment and skip the `make db.up` step.

### Install

```bash
git clone https://github.com/bleuropa/loomkin.git
cd loomkin

# Install deps, start Postgres container, set up the database
make setup

# Start the web UI
make dev
# → http://localhost:4200
```

### Configure

Set your LLM provider API key:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# or
export OPENAI_API_KEY="sk-..."
```

Optionally create a `.loomkin.toml` in your project root:

```toml
[model]
default = "anthropic:claude-sonnet-4-6"
weak = "anthropic:claude-haiku-4-5"

[permissions]
auto_approve = ["file_read", "file_search", "content_search", "directory_list"]
```

[Full configuration reference](docs/configuration.md)

### Run

```bash
# Web UI — streaming chat, file tree, decision graph, team dashboard
mix phx.server
# → http://localhost:4200
```

---

## Features

### Intelligence

- **Decision graph** — persistent DAG of goals, decisions, and outcomes (7 node types, typed edges, confidence tracking). Cascade uncertainty propagation warns downstream nodes when confidence drops. Auto-logging captures lifecycle events. Narrative generation builds timeline summaries. Pulse reports surface coverage gaps and stale decisions. Interactive SVG visualization in the web UI
- **Context mesh** — agents offload context to Keeper processes instead of summarizing it away. Any agent can retrieve the full conversation from any other agent's history. Semantic search across keepers via cheap LLM calls. Total context grows with the task instead of shrinking
- **Keeper intelligence** — keepers track access frequency, staleness, and confidence. Stale knowledge auto-archives. Failure memory keepers capture lessons from errors so agents avoid repeating mistakes
- **Self-introspection** — agents can examine their own decision history and failure patterns via built-in tools, learning from past work
- **Token-aware context window** — automatic budget allocation across system prompt, decision context, repo map, conversation history, and tool definitions with dynamic headroom accounting
- **Tree-sitter repo map** — symbol extraction across 7 languages (Elixir, JS/TS, Python, Ruby, Go, Rust) with ETS caching and regex fallback

### Agent Teams

- **OTP-native** — each agent is a GenServer under a DynamicSupervisor. Spawn in <500ms, communicate via PubSub in microseconds. 100+ concurrent agents per node
- **5 built-in roles** — lead, researcher, coder, reviewer, tester. Each with scoped tools and tailored system prompts. Custom roles and Kin agents configurable via `.loomkin.toml` or the Kin management panel
- **Orchestrator mode** — leads with specialists automatically restrict to coordination-only tools, delegating work instead of doing it themselves
- **Structured handoffs** — when agents hand off tasks, they pass structured context: actions taken, discoveries, files changed, decisions made, and open questions
- **Conversation agents** — any agent can spawn a freeform multi-agent conversation (brainstorm, design review, red team, user panel). A Weaver agent auto-summarizes the outcome
- **Self-healing** — error classification, agent suspension, and ephemeral diagnostician + fixer agents that repair failures autonomously. Per-role healing policies
- **Verification loops** — autonomous write → test → diagnose → fix → re-test cycles. Upstream verifiers auto-spawn on task completion to validate output before dependents proceed
- **Speculative execution** — agents work ahead on likely next steps. If assumptions hold, the work stands. If not, it gets discarded cleanly
- **Task negotiation** — agents can counter-propose task assignments, suggesting better-suited teammates or flagging concerns. Uncontested assignments auto-accept
- **Cross-team communication** — sub-teams discover siblings, send lateral messages, and query agents across team boundaries
- **Structured debate** — propose/critique/revise/vote cycle with policy-driven consensus and convergence tracking
- **Pair programming** — dedicated coder + reviewer pairing with real-time event exchange
- **Per-team budget tracking** — token bucket rate limiting, per-agent spend limits, model escalation chains (cheap model fails twice → auto-escalate)
- **Region-level file locking** — multiple agents safely edit the same file by claiming line ranges or symbols

### Interfaces

- **Mission control UI** — 39 LiveView components, zero handwritten JavaScript. Fixed agent cards with live status, thinking, and tool calls. Comms feed for inter-agent communication. Interactive decision graph. Context library for inspecting keeper state. Permission dashboard with trust policies and audit trail. Settings panel for runtime configuration. Kin management panel for custom agent personas
- **Workspaces** — persistent layer above sessions. Teams, tasks, and progress survive tab closes. Sessions are just how you connect to your workspace
- **Visible message queues** — every agent's pending messages are visible and editable. Reorder, squash, delete, or schedule messages to steer agents without disrupting their current work
- **Skill system** — agents see available skills in their context and load full details on demand. Skills auto-load from disk (`.agents/skills/`), can be authored in-app, published as community snippets, and installed by others
- **MCP server + client** — expose Loomkin's tools to VS Code/Cursor/Zed; consume external tools from Tidewave, HexDocs, and any MCP server. Bidirectional by default
- **Architect/Editor mode** — strong model (e.g. Opus) plans edits, fast model (e.g. Haiku) executes them. Can spawn full teams for complex tasks instead of file-based plans
- **Spawn approval gates** — approve or deny agent spawns from the UI, with auto-approve toggle for trusted workflows

### Infrastructure

- **58 built-in tools** — file ops, glob/regex search, shell, git, LSP diagnostics, decision logging/querying, team management, peer communication, context mesh, verification, self-introspection, conversation spawning, skill loading, acceptance checks
- **16 LLM providers + local** — Anthropic, OpenAI, Google, Z.AI, xAI, Groq, DeepSeek, OpenRouter, Mistral, Cerebras, Together AI, Fireworks AI, Cohere, Perplexity, NVIDIA, Azure. 665+ models via req_llm. Ollama for local LLMs
- **Typed signal bus** — 28+ signal types across 8 domains (agent, team, context, decision, session, system, channel, collaboration) via Jido.Signal. ETS journal for replay
- **LSP client** — compiler errors/warnings from ElixirLS, next-ls, and other language servers
- **File watcher** — OS-native with 200ms debounce, `.gitignore` filtering, automatic ETS index + repo map refresh
- **Workspace persistence** — teams, tasks, and task journals persist in PostgreSQL. Sessions are ephemeral UI overlays
- **Permission system** — per-tool, per-path approval with trust policies, audit trail, and tool hooks
- **LLM retry** — exponential backoff with transient vs permanent error classification
- **Hot code reloading** — update tools, providers, prompts without restarting sessions
- **Telemetry + cost dashboard** — per-session costs, model usage breakdown, tool execution frequency
- **Channel adapters** — Telegram and Discord integrations via telegex and nostrum

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      INTERFACES                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐   │
│  │ LiveView Web  │  │   MCP Svr    │  │ Channel Adapt │   │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘   │
│         └─────────────────┼──────────────────┘           │
├───────────────────────────┼──────────────────────────────┤
│  Workspace Layer          │                              │
│  ┌────────────────────────┴───────────────────────────┐  │
│  │ Workspace (persistent team + task state)            │  │
│  │  ├── Session GenServer (per-connection UI overlay)  │  │
│  │  ├── Agent Teams (DynamicSupervisor + GenServers)   │  │
│  │  ├── Context Window (token-budgeted history)       │  │
│  │  ├── Decision Graph (persistent reasoning memory)  │  │
│  │  └── Permission Manager (trust policies + audit)   │  │
│  └────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────┤
│  Agent Runtime                                           │
│  Conversation Agents │ Self-Healing │ Verification Loop  │
│  Speculative Execution │ Task Negotiation │ Orchestrator │
├──────────────────────────────────────────────────────────┤
│  Tool Layer (58 Actions)                                 │
│  File I/O │ Search │ Shell │ Git │ LSP │ Decisions │     │
│  Team Mgmt │ Peer Comms │ Context Mesh │ Skills │ Verify │
├──────────────────────────────────────────────────────────┤
│  Intelligence                                            │
│  Decision Graph │ Repo Intel │ Keeper Intelligence │     │
│  Failure Memory │ Self-Introspection                     │
├──────────────────────────────────────────────────────────┤
│  Protocols: MCP Server │ MCP Client │ LSP Client         │
├──────────────────────────────────────────────────────────┤
│  LLM Layer: req_llm (16 providers, 665+ models, Ollama) │
├──────────────────────────────────────────────────────────┤
│  Signal Bus │ Telemetry │ Observability                  │
└──────────────────────────────────────────────────────────┘
```

[Full architecture deep dive](docs/architecture.md)

---

## Project Rules

Create a `LOOMKIN.md` in your project root to give Loomkin persistent instructions:

```markdown
# Project Instructions

This is a Phoenix LiveView app using Ecto with PostgreSQL.

## Rules
- Always run `mix format` after editing .ex files
- Run `mix test` before committing
- Use `binary_id` for all primary keys

## Allowed Operations
- Shell: `mix *`, `git *`, `elixir *`
- File Write: `lib/**`, `test/**`, `priv/repo/migrations/**`
- File Write Denied: `config/runtime.exs`, `.env*`
```

---

## Roadmap

Loomkin is in active development. The core agent runtime, team orchestration, and web UI are stable and feature-rich.

- **Done**: Agent teams, decision graph, context mesh, conversation agents, self-healing, orchestrator mode, structured handoffs, verification loops, speculative execution, task negotiation, cross-team communication, skill system, workspaces, keeper intelligence, permission dashboard, settings panel, visibility pipeline, channel adapters, signal bus
- **Now**: Closing the loop (Epic 18) — keeper intelligence, workspace persistence, autonomous verification chains
- **Next**: Vault primitive (generalized knowledge storage), long-horizon coding (multi-day autonomous sessions), platform API

---

## Acknowledgments

Loomkin wouldn't exist without these projects:

- **[Phoenix](https://github.com/phoenixframework/phoenix)** + **[LiveView](https://github.com/phoenixframework/phoenix_live_view)** — the framework that makes a 39-component real-time web UI possible without writing JavaScript. The foundation of everything users see.
- **[Jido](https://github.com/agentjido/jido)** by the AgentJido team — Elixir-native agent framework providing Loomkin's tool system, action composition, signal bus, and shell sandboxing.
- **[Deciduous](https://github.com/juspay/deciduous)** by Juspay — pioneered the concept of structured decision graphs for AI agents. Loomkin's decision graph is a native Elixir implementation of the patterns Deciduous proved out in Rust.
- **[req_llm](https://github.com/agentjido/req_llm)** — unified LLM client for Elixir with 16 providers and 665+ models. Every LLM call in Loomkin goes through req_llm.
- **[Aider](https://github.com/paul-gauthier/aider)** — the gold standard for AI coding assistants. Loomkin's repo map and context packing draw from Aider's approach, with ETS caching and BEAM-native parallelism for symbol extraction.
- **[Claude Code](https://claude.ai/claude-code)** — Anthropic's CLI agent that demonstrated the power of tool-using AI assistants and multi-agent coordination patterns.

---

## Contributing

Loomkin is in active development. Contributions welcome. **2,600+ tests across 216 files. ~73K LOC application code. ~40K LOC tests.**

```bash
# Full setup (Docker, deps, database)
make setup

# Start the dev server
make dev

# Run tests
make test

# Format code
make format

# Database lifecycle
make db.up      # start Postgres container
make db.down    # stop Postgres container
make db.reset   # drop, create, migrate, seed
```

---

## License

MIT
