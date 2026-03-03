# Epic 7: Channel Adapters (Telegram & Discord)

## Overview

Enable users to interact with their Loomkin agent teams from Telegram and Discord, turning messaging apps into mobile/desktop mission control surfaces. Users can monitor agent activity, respond to `ask_user` questions, send directives to agents, and receive real-time notifications — all without opening the web UI.

The design uses a behaviour-based adapter pattern so adding future channels (Slack, WhatsApp, Matrix) requires only implementing a new adapter module, with zero changes to core logic.

## Architecture

```
                          +--------------------+
                          |   WorkspaceLive    |  (existing web UI)
                          +--------+-----------+
                                   |
                                   | PubSub "team:*"
                                   v
+------------------+     +--------------------+     +------------------+
|  Telegram Bot    | <-->|  Channels.Router   | <-->|  Discord Bot     |
|  (Telegex)       |     |                    |     |  (Nostrum)       |
+--------+---------+     +--------+-----------+     +--------+---------+
         |                        |                          |
         v                        v                          v
+------------------+     +--------------------+     +------------------+
| Telegram.Adapter |     | Channels.Adapter   |     | Discord.Adapter  |
| (implements      |     | (behaviour)        |     | (implements      |
|  behaviour)      |     +--------------------+     |  behaviour)      |
+--------+---------+            |                   +--------+---------+
         |                      v                            |
         |              +--------------------+               |
         +------------->| Channels.Bridge    |<--------------+
                        | (per-binding        |
                        |  GenServer)         |
                        +--------+-----------+
                                 |
                        PubSub subscribe/broadcast
                                 |
                        +--------v-----------+
                        | Teams.Agent /      |
                        | Teams.Manager /    |
                        | Teams.Comms        |
                        +--------------------+
```

### Key Concepts

- **Binding**: A link between a channel conversation (Telegram chat_id / Discord channel_id) and a Loomkin team_id. Stored in SQLite via Ecto.
- **Bridge**: A per-binding GenServer that subscribes to PubSub topics for its bound team and forwards relevant events to the channel adapter. Also routes inbound messages from the channel to the team.
- **Adapter**: A behaviour module that normalizes platform-specific message formats (Markdown flavors, buttons/keyboards, embeds) into a common internal format and vice versa.
- **Router**: The central coordinator that receives inbound messages from adapters, resolves bindings, and dispatches to the appropriate Bridge.

## Library Choices

| Channel  | Library   | Version | Rationale |
|----------|-----------|---------|-----------|
| Telegram | `telegex` | ~> 1.8  | Auto-generated from official docs, fastest API adaptation, supports webhooks + polling, Bandit-compatible |
| Discord  | `nostrum` | ~> 0.10 | Most mature Elixir Discord library, slash commands, interactions, button components, multi-node support |

**Why Telegex over ExGram**: Telegex generates code from official Telegram API docs, meaning new Bot API features are available faster. It also has cleaner webhook integration with Bandit (which Loomkin already uses).

**Why Nostrum**: It is the only actively maintained, production-quality Discord library for Elixir. Its consumer-based event handling maps well to our GenServer architecture.

## Sub-Tasks

### 7.1 — Adapter Behaviour & Common Types
**Complexity**: Small
**Dependencies**: None
**Description**: Define the `Loomkin.Channels.Adapter` behaviour and shared types.

**Files to create**:
- `lib/loomkin/channels/adapter.ex` — behaviour with callbacks
- `lib/loomkin/channels/message.ex` — common message struct

**Behaviour callbacks**:
```elixir
@callback send_text(binding, text, opts) :: :ok | {:error, term()}
@callback send_question(binding, question, options) :: :ok | {:error, term()}
@callback send_activity(binding, event) :: :ok | {:error, term()}
@callback format_agent_message(agent_name, content) :: String.t()
@callback parse_inbound(raw_event) :: {:message, text, metadata} | {:callback, callback_id, data} | :ignore
```

**Common message struct**:
```elixir
defstruct [:direction, :channel, :binding_id, :sender, :content, :metadata, :timestamp]
# direction: :inbound | :outbound
# channel: :telegram | :discord | :web
```

---

### 7.2 — Binding Schema & Management
**Complexity**: Small
**Dependencies**: 7.1
**Description**: Ecto schema and context module for managing channel-to-team bindings.

**Files to create**:
- `lib/loomkin/channels/binding.ex` — Ecto schema
- `lib/loomkin/channels/bindings.ex` — context (CRUD)
- `priv/repo/migrations/*_create_channel_bindings.exs`

**Schema fields**:
- `id` (UUID primary key)
- `channel` (:telegram | :discord)
- `channel_id` (string — Telegram chat_id or Discord channel_id)
- `team_id` (string — Loomkin team ID)
- `user_id` (string — optional, for auth)
- `config` (map — channel-specific settings like notification preferences)
- `active` (boolean)
- timestamps

**Context API**:
- `create_binding/1`, `get_binding/1`, `get_by_channel/2`
- `list_bindings_for_team/1`, `deactivate_binding/1`
- `find_or_create/3` — idempotent upsert

---

### 7.3 — Channel Bridge GenServer
**Complexity**: Medium
**Dependencies**: 7.1, 7.2
**Description**: Per-binding GenServer that bridges PubSub events to channel output and routes inbound messages to the team.

**Files to create**:
- `lib/loomkin/channels/bridge.ex`
- `lib/loomkin/channels/bridge_supervisor.ex`

**Bridge responsibilities**:
1. On start, subscribe to `"team:#{team_id}"`, `"team:#{team_id}:tasks"`, `"team:#{team_id}:context"`
2. Receive PubSub events and forward to adapter: agent messages, tool activity, ask_user questions, collaboration events, errors
3. Receive inbound messages from adapter and dispatch: either `Teams.Agent.send_message/2` for direct replies or `Session.send_message/2` for team-level directives
4. Handle `ask_user` flow: when an `{:ask_user_question, payload}` event arrives, call `adapter.send_question/3` to show buttons/keyboard, then wait for callback and route the answer back via the existing `{:ask_user, question_id}` Registry mechanism
5. Rate-limit outbound messages to avoid Telegram/Discord API limits (token bucket)

**Event filtering**:
Not all PubSub events should be forwarded. The bridge filters by importance:
- Always forward: `ask_user_question`, `agent_error`, `team_dissolved`
- Forward on activity: `new_message` (final answers only, not tool results), `collab_event` (conflicts, consensus)
- Suppress: `stream_delta`, `tool_executing`, `usage` (too noisy for chat)

---

### 7.4 — Channel Router
**Complexity**: Small
**Dependencies**: 7.2, 7.3
**Description**: Receives inbound events from adapters, resolves bindings, and dispatches to Bridge processes.

**Files to create**:
- `lib/loomkin/channels/router.ex`

**Router responsibilities**:
- `handle_inbound/3` — looks up binding by `{channel, channel_id}`, finds or starts Bridge, forwards message
- `handle_callback/3` — handles button/keyboard callbacks (ask_user answers)
- Slash command / bot command parsing: `/bind <team_id>`, `/unbind`, `/status`, `/agents`, `/ask <agent> <message>`

---

### 7.5 — Telegram Adapter
**Complexity**: Medium
**Dependencies**: 7.1, 7.4
**Description**: Implement the Adapter behaviour for Telegram using Telegex.

**Files to create**:
- `lib/loomkin/channels/telegram/adapter.ex`
- `lib/loomkin/channels/telegram/webhook.ex` (Plug-based webhook handler)
- `lib/loomkin/channels/telegram/formatter.ex`

**Key implementation details**:
- **Webhooks**: Use Telegex's webhook support, mount under `/api/webhooks/telegram` in the Phoenix router
- **Inline keyboards**: Map `ask_user` options to `InlineKeyboardButton` with callback_data
- **Markdown**: Telegram uses MarkdownV2 — need a converter from standard markdown
- **Commands**: `/bind`, `/unbind`, `/status`, `/agents`, `/ask`
- **Message splitting**: Telegram has a 4096 char limit — split long agent responses
- **Rate limiting**: Telegram limits 30 msg/sec to different chats, 20 msg/min to same chat

---

### 7.6 — Discord Adapter
**Complexity**: Medium
**Dependencies**: 7.1, 7.4
**Description**: Implement the Adapter behaviour for Discord using Nostrum.

**Files to create**:
- `lib/loomkin/channels/discord/adapter.ex`
- `lib/loomkin/channels/discord/consumer.ex` (Nostrum consumer for events)
- `lib/loomkin/channels/discord/formatter.ex`

**Key implementation details**:
- **Slash commands**: Register `/loom bind`, `/loom unbind`, `/loom status`, `/loom agents`, `/loom ask`
- **Buttons**: Map `ask_user` options to Discord ActionRow with Button components
- **Embeds**: Use Discord embeds for agent activity summaries (colored sidebar by agent role)
- **Threads**: Optionally create Discord threads per agent for focused conversation
- **Markdown**: Discord uses a slightly different markdown flavor — convert accordingly
- **Message splitting**: Discord has a 2000 char limit — split long responses
- **Rate limiting**: Nostrum handles Discord rate limits internally

---

### 7.7 — Configuration & Authentication
**Complexity**: Small
**Dependencies**: 7.5, 7.6
**Description**: Configuration system for channel credentials and user authentication.

**Files to modify**:
- `lib/loomkin/config.ex` — add channel config loading
- `.loomkin.toml` example — document channel config format

**Configuration format** (in `.loomkin.toml`):
```toml
[channels.telegram]
enabled = true
bot_token = "${TELEGRAM_BOT_TOKEN}"
webhook_url = "https://your-domain.com/api/webhooks/telegram"
allowed_chat_ids = []  # empty = allow all

[channels.discord]
enabled = true
bot_token = "${DISCORD_BOT_TOKEN}"
guild_ids = []  # empty = allow all
```

**Authentication model**:
- Phase 1: Simple — any user in an allowed chat/guild can interact. Binding is per-chat/channel.
- Phase 2 (future): Token-based auth — users run `/auth <token>` to link their channel identity to a Loomkin account.

---

### 7.8 — Supervisor & Application Integration
**Complexity**: Small
**Dependencies**: 7.5, 7.6, 7.7
**Description**: Wire everything into the application supervision tree.

**Files to modify**:
- `lib/loomkin/application.ex` — add `Loomkin.Channels.Supervisor`
- `lib/loomkin/channels/supervisor.ex` — supervise adapter processes and bridge supervisor

**Supervision tree addition**:
```
Loomkin.Channels.Supervisor
├── Loomkin.Channels.Telegram.Webhook  (if enabled)
├── Nostrum.Application                (if enabled, via Nostrum)
├── Loomkin.Channels.Discord.Consumer  (if enabled)
└── DynamicSupervisor (Bridge processes)
```

---

### 7.9 — Web UI Integration
**Complexity**: Small
**Dependencies**: 7.2, 7.3
**Description**: Show channel binding status and activity in the mission control workspace.

**Files to modify**:
- `lib/loomkin_web/live/workspace_live.ex` — show channel indicators on agent roster
- `lib/loomkin_web/live/agent_roster_component.ex` — channel badge icons

**What to show**:
- Badge on team header indicating active channels (Telegram icon, Discord icon)
- In activity feed: show when messages arrive from/go to external channels
- Binding management in command palette: "Connect Telegram", "Connect Discord"

---

### 7.10 — Testing
**Complexity**: Medium
**Dependencies**: 7.1-7.9
**Description**: Test suite for the channel adapter system.

**Files to create**:
- `test/loomkin/channels/adapter_test.exs` — behaviour contract tests
- `test/loomkin/channels/binding_test.exs` — schema/context tests
- `test/loomkin/channels/bridge_test.exs` — PubSub forwarding tests
- `test/loomkin/channels/router_test.exs` — routing tests
- `test/loomkin/channels/telegram/adapter_test.exs` — Telegram-specific formatting
- `test/loomkin/channels/discord/adapter_test.exs` — Discord-specific formatting

**Testing strategy**:
- Use Mox to mock adapter callbacks for bridge/router tests
- Test message formatting with known input/output pairs
- Test binding CRUD with Ecto sandbox
- Test PubSub event forwarding with in-process PubSub
- Integration tests with mock webhook payloads (no real API calls)

## Implementation Order

1. **7.1** Adapter Behaviour & Types (foundation)
2. **7.2** Binding Schema (database layer)
3. **7.3** Bridge GenServer (core pub/sub bridge)
4. **7.4** Router (inbound dispatch)
5. **7.5** Telegram Adapter (first channel)
6. **7.7** Configuration (needed to start bots)
7. **7.8** Supervisor & Application (wire it up)
8. **7.10** Testing (validate Telegram end-to-end)
9. **7.6** Discord Adapter (second channel)
10. **7.9** Web UI Integration (polish)

## ask_user Integration

The existing `ask_user` tool (`lib/loomkin/tools/ask_user.ex`) broadcasts `{:ask_user_question, payload}` on the team PubSub topic. The Bridge subscribes to this topic and:

1. Receives `{:ask_user_question, %{question_id, agent_name, question, options}}`
2. Calls `adapter.send_question(binding, question, options)` which renders inline keyboard (Telegram) or button components (Discord)
3. User taps a button, adapter receives callback, routes to Bridge
4. Bridge looks up the agent's caller via `Registry.lookup(AgentRegistry, {:ask_user, question_id})`
5. Sends `{:ask_user_answer, question_id, selected_option}` to the waiting agent process

This creates a seamless mobile-friendly experience for agent-to-human interaction with zero changes to the existing `AskUser` tool.

## Risks & Open Questions

1. **Webhook URL requirement**: Telegram webhooks need a public HTTPS URL. For local dev, users would need ngrok/cloudflared or fall back to polling mode. The adapter should support both modes.

2. **Multi-user teams**: If multiple Telegram users are in the same group chat bound to a team, who gets the `ask_user` questions? Options: broadcast to all (first responder wins) vs. designate an operator.

3. **Message volume**: Active agent teams can produce many events. The Bridge must aggressively filter and batch/summarize to avoid flooding the chat. Consider a digest mode (periodic summary) vs. live mode (real-time).

4. **State after restart**: Bridge processes are ephemeral. On app restart, active bindings should be loaded from the DB and bridges re-started. The supervisor handles this.

5. **Discord Gateway vs. HTTP**: Nostrum uses the Gateway (WebSocket) which requires a persistent connection. This is fine for a server deployment but adds memory overhead. For webhook-only Discord interactions, we could use `discord_interactions` library instead — but it lacks full bot capabilities.

6. **Security**: Bot tokens must be kept secret. Use environment variables, not config files. The binding system should validate that chat/channel IDs are authorized before accepting commands.

7. **Concurrent ask_user**: If an agent sends an `ask_user` question and the user is on both web and Telegram, both surfaces show the question. The first answer wins (existing Registry mechanism handles this), but the other surface should show the question as answered.
