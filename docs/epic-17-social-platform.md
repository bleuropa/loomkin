# Epic 17: Social Platform — Auth, Sharing, and Community

## Problem Statement

Loomkin today is a single-user local tool. There's no concept of user accounts, no way to save a great agent chat for later, no way to share a skill you've crafted with someone else, and no way to discover what other people are building. Skills live as static markdown files on disk. Conversations evaporate when the process dies. Kin agent configs are local-only.

This means users can't do things like:
- Share a skill they've refined with the community
- Fork someone else's prompt and adapt it to their workflow
- Save an agent chat that produced great results
- Browse trending skills or prompts from other users
- Install community skills into their project with one click
- Have a persistent identity across sessions

The vision: a **gist-like system** where skills, prompts, kin agents, and chat logs are first-class shareable objects. Private by default, publishable when ready. Forkable. Favoritable. Installable.

## Why This Matters Now

Loomkin is approaching deployment. The jump from local tool to hosted platform requires user accounts as a foundation. Building auth first (via `mix phx.gen.auth`) gives us the identity layer everything else depends on: ownership, permissions, social graph, billing (later).

## Dual-Mode Architecture

Loomkin operates in two modes, controlled by a single config flag:

```elixir
# config/dev.exs
config :loomkin, :multi_tenant, false

# config/runtime.exs (prod, when MULTI_TENANT is set)
config :loomkin, :multi_tenant,
  System.get_env("MULTI_TENANT", "false") == "true"
```

| Aspect | Local Mode | Deployed Mode |
|--------|-----------|---------------|
| Auth | None — straight to project picker | Required — login/register wall |
| Homepage | Project picker (current `/`) | Social dashboard + feed |
| `user_id` columns | Always `nil` (single implicit user) | Required, non-nullable via auth |
| Social features | Hidden — routes don't mount | Full — browse, fork, favorite |
| Skills | Read from `.agents/skills/` on disk | DB-backed + disk sync |
| Snippets | Not available | Full CRUD + sharing |

The router branches on this flag. In local mode, auth modules load but no auth pipeline is enforced. Zero friction for local development.

## Dependencies

- `mix phx.gen.auth` — ships with Phoenix 1.8, no external deps (uses bcrypt)
- No new hex packages required for core social features
- Existing `assent` dep can be extended for GitHub OAuth login (phase 2)

---

## 17.1: User Authentication — `mix phx.gen.auth`

**Complexity:** Small
**Dependencies:** None

Run the Phoenix auth generator to scaffold the full auth system:

```bash
mix phx.gen.auth Accounts User users
```

This gives us:
- `users` table with email, hashed_password, confirmed_at
- `users_tokens` table for session + email confirmation tokens
- `Loomkin.Accounts` context with registration, login, password reset
- Auth plugs: `fetch_current_user`, `require_authenticated_user`, `redirect_if_user_is_authenticated`
- LiveView auth helpers via `on_mount` hooks
- Registration, login, settings, confirmation, and reset password LiveViews

### Post-Generation Work

1. **Add `username` field** to users table (unique, URL-safe, for public profiles)
2. **Add `display_name` and `avatar_url`** fields (optional, for social features)
3. **Wire multi-tenant gate** into router:

```elixir
# router.ex
pipeline :require_auth do
  plug :fetch_current_user
  plug :require_authenticated_user
end

scope "/", LoomkinWeb do
  pipe_through [:browser]

  # Public routes (deployed mode only, gated by multi_tenant config)
  live "/explore", ExploreLive, :index
end

scope "/", LoomkinWeb do
  pipe_through [:browser, :require_auth_if_multi_tenant]

  live "/", HomeLive, :index
  live "/sessions/new", WorkspaceLive, :new
  live "/sessions/:session_id", WorkspaceLive, :show
  # ... existing routes
end
```

4. **`require_auth_if_multi_tenant` plug** — passes through in local mode, enforces auth in deployed mode:

```elixir
defp require_auth_if_multi_tenant(conn, _opts) do
  if Application.get_env(:loomkin, :multi_tenant) do
    require_authenticated_user(conn, [])
  else
    conn
  end
end
```

5. **Add `user_id` foreign key** to existing tables via migration:
   - `sessions` — who owns this session
   - `kin_agents` — who created this agent config
   - `auth_tokens` — whose API keys are these
   - `permission_grants` — whose approvals

### Acceptance Criteria

- [ ] `mix phx.gen.auth` scaffolding generated and compiling
- [ ] `username`, `display_name`, `avatar_url` added to users
- [ ] Multi-tenant gate plug working (local mode skips auth, deployed mode enforces)
- [ ] Existing tables have `user_id` foreign key
- [ ] `mix ecto.reset && mix test` passes
- [ ] Registration and login flow works end-to-end in deployed mode
- [ ] Local mode boots straight to project picker with no auth prompt

---

## 17.2: Snippets — The Shareable Primitive

**Complexity:** Medium
**Dependencies:** 17.1

A **snippet** is the universal container for shareable content — like a GitHub gist but for AI workflows. Every shareable thing in Loomkin is a snippet.

### Schema

```elixir
defmodule Loomkin.Schemas.Snippet do
  use Ecto.Schema

  schema "snippets" do
    belongs_to :user, Loomkin.Schemas.User
    belongs_to :forked_from, __MODULE__

    field :title, :string
    field :description, :string
    field :type, Ecto.Enum, values: [:skill, :prompt, :kin_agent, :chat_log]
    field :visibility, Ecto.Enum, values: [:private, :unlisted, :public], default: :private
    field :content, :map          # type-specific payload (see below)
    field :tags, {:array, :string}, default: []
    field :slug, :string          # URL-safe identifier (unique per user)
    field :fork_count, :integer, default: 0
    field :favorite_count, :integer, default: 0
    field :version, :integer, default: 1

    has_many :favorites, Loomkin.Schemas.Favorite
    has_many :forks, __MODULE__, foreign_key: :forked_from_id

    timestamps(type: :utc_datetime)
  end
end
```

### Content Shapes by Type

```elixir
# :skill — parsed from SKILL.md format
%{
  "body" => "## Purpose\n...",           # markdown content
  "frontmatter" => %{                    # YAML frontmatter
    "name" => "elixir-expert",
    "description" => "..."
  }
}

# :prompt — user-created prompt template
%{
  "system_prompt" => "You are a...",
  "user_prompt_template" => "Given {context}, ...",
  "variables" => ["context", "language"]
}

# :kin_agent — agent configuration
%{
  "role" => "coder",
  "system_prompt_extra" => "...",
  "model_override" => "anthropic:claude-sonnet-4-20250514",
  "tool_overrides" => %{},
  "potency" => 70,
  "spawn_context" => "When the user needs..."
}

# :chat_log — saved conversation snapshot
%{
  "messages" => [...],                   # list of {role, content} pairs
  "model" => "anthropic:claude-sonnet-4-20250514",
  "agent_count" => 3,
  "summary" => "Discussed approach to..."
}
```

### Context Module

```elixir
defmodule Loomkin.Social do
  # Snippet CRUD
  def create_snippet(user, attrs)
  def update_snippet(snippet, attrs)
  def delete_snippet(snippet)
  def get_snippet!(id)
  def get_snippet_by_slug(username, slug)

  # Listing & Discovery
  def list_user_snippets(user, opts \\ [])    # filter by type, visibility
  def list_public_snippets(opts \\ [])         # paginated, filterable
  def search_snippets(query, opts \\ [])
  def trending_snippets(opts \\ [])            # by recent favorites/forks

  # Social Actions
  def fork_snippet(user, snippet)
  def toggle_favorite(user, snippet)
  def favorited?(user, snippet)
end
```

### Acceptance Criteria

- [ ] `snippets` table created with all fields
- [ ] Snippet changeset validates title, type, visibility, content shape
- [ ] `Loomkin.Social` context with full CRUD
- [ ] Fork creates a deep copy with `forked_from_id` set, increments parent `fork_count`
- [ ] Favorite toggle works, updates `favorite_count` denormalized counter
- [ ] Slug auto-generated from title, unique per user
- [ ] Pagination on listing queries

---

## 17.3: Favorites

**Complexity:** Small
**Dependencies:** 17.1, 17.2

```elixir
defmodule Loomkin.Schemas.Favorite do
  use Ecto.Schema

  schema "favorites" do
    belongs_to :user, Loomkin.Schemas.User
    belongs_to :snippet, Loomkin.Schemas.Snippet

    timestamps(type: :utc_datetime)
  end
end
```

Unique constraint on `{user_id, snippet_id}`. Toggle via upsert/delete in `Social.toggle_favorite/2`. Updates `snippet.favorite_count` via database trigger or explicit increment.

### Acceptance Criteria

- [ ] `favorites` table with unique index on `{user_id, snippet_id}`
- [ ] Toggle favorite creates or deletes the record
- [ ] `favorite_count` on snippet stays in sync
- [ ] `Social.favorited?/2` returns boolean

---

## 17.4: Homepage — Social Dashboard

**Complexity:** Medium
**Dependencies:** 17.1, 17.2, 17.3

**Design requirement:** This is the first thing users see when they open the deployed app. It must feel bespoke and high-quality — not generic scaffolding. Use the `frontend-design` skill when building this to ensure polished typography, spacing, color, motion, and layout. The homepage sets the tone for the entire platform.

The new authenticated homepage replaces `ProjectPickerLive` as the `/` route in deployed mode. In local mode, `/` still routes to the project picker.

### Layout

```
┌─────────────────────────────────────────────────────────┐
│  Loomkin                    [Explore]  [@username ▾]    │
├────────────────────────┬────────────────────────────────┤
│                        │                                │
│  YOUR PROJECTS         │  COMMUNITY FEED                │
│  ┌──────────────────┐  │                                │
│  │ loom        [►]  │  │  @alice published              │
│  │ loreforge   [►]  │  │  "elixir-expert" skill         │
│  │ byok        [►]  │  │  ★ 12  ⑂ 3                    │
│  └──────────────────┘  │                                │
│                        │  @bob forked                    │
│  YOUR SNIPPETS         │  "react-reviewer" from @carol   │
│  ┌──────────────────┐  │                                │
│  │ Skills (3)    [+]│  │  Trending This Week             │
│  │ Prompts (5)   [+]│  │  1. debug-detective  ★ 42      │
│  │ Chat Logs (2) [+]│  │  2. api-designer     ★ 31      │
│  │ Kin Agents (4)[+]│  │  3. test-architect   ★ 28      │
│  └──────────────────┘  │                                │
│                        │                                │
│  FAVORITES             │  RECENT ACTIVITY                │
│  ★ code-review prompt  │  You forked "css-grid"          │
│  ★ brainstorm template │  3 new public skills today      │
│  ★ debug-detective     │  @carol favorited your prompt   │
│                        │                                │
├────────────────────────┴────────────────────────────────┤
│  Recent Sessions: "oauth refactor" · "epic 6 planning"  │
└─────────────────────────────────────────────────────────┘
```

### Implementation

- `HomeLive` — new LiveView at `/` (deployed mode)
- Left column: user's projects (from existing project picker logic), snippet counts by type, favorites
- Right column: community feed (recent public snippets, forks, trending)
- Activity feed via `Loomkin.Social.recent_activity/1`
- Project cards link to `/sessions/new?project_path=...`
- Snippet counts link to filtered snippet list views

### Acceptance Criteria

- [ ] `HomeLive` renders at `/` in deployed mode
- [ ] Project picker still at `/` in local mode (no regression)
- [ ] Left column shows user's projects, snippet summary, favorites
- [ ] Right column shows community feed with recent public snippets
- [ ] Trending section shows top snippets by recent favorite velocity
- [ ] Recent sessions row links to existing session views
- [ ] Responsive layout (stacks on mobile)
- [ ] Polished, bespoke visual design (built with `frontend-design` skill — no generic scaffolding look)

---

## 17.5: Snippet Detail & Profile Views

**Complexity:** Medium
**Dependencies:** 17.2, 17.4

### Routes

```elixir
live "/@:username", ProfileLive, :show                    # user profile
live "/@:username/:slug", SnippetLive, :show              # snippet detail
live "/snippets/new", SnippetLive, :new                   # create snippet
live "/snippets/:id/edit", SnippetLive, :edit             # edit snippet
live "/explore", ExploreLive, :index                      # browse all public
```

### Snippet Detail View

- Rendered markdown for skills/prompts
- Structured display for kin agents (role, potency, tools, etc.)
- Scrollable chat log viewer for saved conversations
- Fork button, favorite button, "Install to project" button
- Fork lineage — link to parent snippet if forked
- Fork count and favorite count

### Profile View

- Username, display name, avatar
- Public snippets listed by type
- Total fork and favorite counts

### Explore View

- Filterable grid/list of public snippets
- Filter by type (skill, prompt, kin_agent, chat_log)
- Sort by: recent, most favorited, most forked
- Search by title/description/tags
- Available to unauthenticated users in deployed mode (browse before signup)

### Acceptance Criteria

- [ ] Snippet detail page renders all 4 content types correctly
- [ ] Fork button creates copy under current user, redirects to their copy
- [ ] Favorite button toggles with optimistic UI update
- [ ] Profile page lists user's public snippets
- [ ] Explore page with filtering, sorting, and search
- [ ] Explore accessible without login (deployed mode)

---

## 17.6: Skill Management — Import, Edit, Install

**Complexity:** Medium
**Dependencies:** 17.2

Bridge between the existing `.agents/skills/` directory system and the new snippet-backed skill storage.

### Import Flow

Parse existing `SKILL.md` files into snippet records:

```elixir
defmodule Loomkin.Social.SkillImporter do
  def import_from_disk(user, project_path) do
    skills_dir = Path.join(project_path, ".agents/skills")

    skills_dir
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(skills_dir, &1)))
    |> Enum.map(fn dir ->
      skill_path = Path.join([skills_dir, dir, "SKILL.md"])
      {frontmatter, body} = parse_skill_md(skill_path)
      Social.create_snippet(user, %{
        title: frontmatter["name"],
        description: frontmatter["description"],
        type: :skill,
        content: %{"frontmatter" => frontmatter, "body" => body},
        visibility: :private
      })
    end)
  end
end
```

### Install Flow (Snippet → Disk)

"Install to project" writes a snippet back to `.agents/skills/`:

```elixir
defmodule Loomkin.Social.SkillInstaller do
  def install_to_project(snippet, project_path) do
    name = snippet.content["frontmatter"]["name"]
    dir = Path.join([project_path, ".agents/skills", name])
    File.mkdir_p!(dir)

    content = """
    ---
    name: #{name}
    description: #{snippet.content["frontmatter"]["description"]}
    ---

    #{snippet.content["body"]}
    """

    File.write!(Path.join(dir, "SKILL.md"), content)
  end
end
```

### Skill Editor

- LiveView form for editing skill content (markdown textarea with preview)
- Frontmatter fields as structured form inputs (name, description, tags)
- "Save" updates the snippet in DB
- "Install to project" button writes to disk (prompts for project path if multiple)
- "Publish" toggles visibility to `:public`

### Acceptance Criteria

- [ ] Import all skills from `.agents/skills/` into snippet records
- [ ] Install writes snippet back to disk in correct SKILL.md format
- [ ] Skill editor with markdown preview
- [ ] Frontmatter fields editable as form inputs
- [ ] Install button with project path selection
- [ ] Round-trip: import → edit → install produces identical SKILL.md

---

## 17.7: Chat Log Saving

**Complexity:** Small
**Dependencies:** 17.2

Add a "Save this chat" action to WorkspaceLive that snapshots the current session's messages into a snippet.

### Implementation

1. **"Save Chat" button** in WorkspaceLive toolbar
2. Collects messages from `Loomkin.Schemas.Message` for the session
3. Prompts user for title, description, tags, visibility
4. Creates snippet with type `:chat_log` and message snapshot in content
5. Chat logs are immutable snapshots — editing the title/description is fine, but the messages are frozen

### Acceptance Criteria

- [ ] "Save Chat" button in workspace UI
- [ ] Modal for title, description, tags, visibility
- [ ] Creates chat_log snippet with full message history
- [ ] Chat log viewer renders messages with role styling
- [ ] Saved chat appears in user's snippet list

---

## 17.8: GitHub OAuth Login (Optional Enhancement)

**Complexity:** Small
**Dependencies:** 17.1

Extend the existing `assent` integration to support GitHub OAuth for user login (not just API provider tokens). Natural fit for the developer audience.

### Implementation

1. Add GitHub OAuth strategy via `assent`
2. Link GitHub identity to Loomkin user account
3. Pull avatar and display name from GitHub profile
4. Support both email/password and GitHub login

### Acceptance Criteria

- [ ] GitHub OAuth login flow works end-to-end
- [ ] New users can register via GitHub
- [ ] Existing users can link GitHub account
- [ ] Avatar and display name populated from GitHub

---

## 17.9: Social Graph — Follows & Live Activity

**Complexity:** Medium
**Dependencies:** 17.1, 17.4

Add a follow system and real-time activity presence so users can see what their network is up to.

### Why This Is Exciting

Every agent in Loomkin is a live BEAM process. That means "Alice is orchestrating 4 agents on a refactor" isn't a polling query — it's a PubSub event. Real-time social activity is nearly free on this stack.

### Schema

```elixir
defmodule Loomkin.Schemas.Follow do
  use Ecto.Schema

  schema "follows" do
    belongs_to :follower, Loomkin.Schemas.User
    belongs_to :followed, Loomkin.Schemas.User

    timestamps(type: :utc_datetime)
  end
end
```

Asymmetric (Twitter-style, not Facebook-style). Unique index on `{follower_id, followed_id}`.

### Live Activity Presence

Use `Phoenix.Presence` to track what users are actively orchestrating:

```elixir
# When a user has active sessions, broadcast presence metadata:
%{
  user_id: user.id,
  username: user.username,
  active_sessions: [
    %{
      title: "oauth refactor",
      agent_count: 4,
      visibility: :public,        # only public sessions shown to followers
      started_at: ~U[2026-03-15 10:30:00Z]
    }
  ]
}
```

Followers see a live feed on the homepage:
- "@alice is orchestrating 4 agents — oauth refactor" (links to public session if shared)
- "@bob has 2 kin agents active" (count only if session is private)
- Activity dots on profile avatars (green = active, dim = idle)

### Social Context Extensions

```elixir
defmodule Loomkin.Social do
  # Follow management
  def follow(follower, followed)
  def unfollow(follower, followed)
  def following?(follower, followed)
  def list_followers(user, opts \\ [])
  def list_following(user, opts \\ [])
  def follower_count(user)
  def following_count(user)

  # Activity feed (follows-scoped)
  def following_activity(user, opts \\ [])      # snippets + live sessions from followed users
  def live_sessions_for_user(user)               # active public sessions with agent counts
end
```

### Homepage Integration

The community feed on HomeLive gets a "Following" tab alongside "Trending":

```
[Following]  [Trending]  [Recent]

@alice is orchestrating 4 agents        ● live
  "oauth refactor" — 12 min ago

@bob published "debug-detective" skill
  ★ 3  ⑂ 1 — 2 hours ago

@carol forked your "api-designer" prompt
  — 5 hours ago
```

### Profile Integration

Profile pages show follower/following counts and a follow/unfollow button:

```
@alice                          [Following ✓]
Display Name · 12 public snippets
42 followers · 18 following
```

### Acceptance Criteria

- [ ] `follows` table with unique index on `{follower_id, followed_id}`
- [ ] Follow/unfollow toggle in Social context
- [ ] Follower/following counts on profile
- [ ] Follow button on profile pages
- [ ] Live activity via Phoenix.Presence — active sessions with agent counts
- [ ] "Following" tab on homepage feed showing followed users' activity
- [ ] Only public sessions visible to followers (private sessions show count only)
- [ ] Activity dots on avatars (green when orchestrating, dim when idle)

---

## 17.10: Social Side Panel — In-Workspace Activity Feed

**Complexity:** Medium
**Dependencies:** 17.9

A persistent, collapsible social panel inside WorkspaceLive so users stay connected to their network without leaving their work. Think Discord's friend activity sidebar — always there, never in the way.

### Why

The homepage is great for discovery, but once you're deep in a coding session you don't want to navigate away just to see what's happening. The social panel keeps ambient awareness of your network while you work.

### Design

Slides in from the right edge of WorkspaceLive (or collapses to an icon strip). Three sections:

```
┌──────────────────────┐
│  SOCIAL          [×] │
├──────────────────────┤
│  LIVE NOW             │
│  ● @alice  4 agents   │
│    "oauth refactor"   │
│  ● @bob    2 agents   │
│    "api redesign"     │
│  ○ @carol  idle       │
├──────────────────────┤
│  ACTIVITY             │
│  @alice published     │
│  "debug-detective"    │
│  ★ 3 — 12 min ago    │
│                       │
│  @bob forked your     │
│  "api-designer"       │
│  — 1 hour ago         │
├──────────────────────┤
│  NOTIFICATIONS        │
│  @carol favorited     │
│  your "brainstorm"    │
│  — 3 hours ago        │
└──────────────────────┘
```

### Implementation

1. **`SocialPanelComponent`** — new functional component in `lib/loomkin_web/components/`
2. **Mount in WorkspaceLive** — only when `multi_tenant` is true (local mode: no panel)
3. **"Live Now" section** — subscribes to `Phoenix.Presence` for followed users, shows active sessions + agent counts. Updates in real-time via PubSub
4. **"Activity" section** — recent snippets/forks from followed users via `Social.following_activity/2`. Polls or subscribes for updates
5. **"Notifications" section** — when someone favorites/forks your content. New schema or lightweight in-memory tracking
6. **Toggle button** — icon in the WorkspaceLive toolbar (people icon or similar). Persists open/closed state in localStorage via existing `WorkspaceState` hook
7. **Collapsible** — slides to a thin icon strip showing just activity dots when collapsed
8. **Does NOT interfere** with existing Context Inspector panel on the right — could share the same side or live on opposite side. Evaluate during implementation

### Acceptance Criteria

- [ ] SocialPanelComponent renders in WorkspaceLive (deployed mode only)
- [ ] "Live Now" shows followed users' active sessions via Presence
- [ ] "Activity" shows recent followed-user snippets/forks
- [ ] "Notifications" shows interactions with your content
- [ ] Toggle button in toolbar, state persisted in localStorage
- [ ] Collapsible to icon strip — doesn't eat screen space when closed
- [ ] Does not render in local (non-multi-tenant) mode
- [ ] Polished design matching homepage aesthetic (use `frontend-design` skill)

---

## Implementation Order

```
17.1 Auth (foundation)
  │
  ├─► 17.2 Snippets (core primitive)
  │     │
  │     ├─► 17.3 Favorites
  │     │     │
  │     │     └─► 17.4 Homepage
  │     │           │
  │     │           ├─► 17.5 Detail & Profile Views
  │     │           │
  │     │           └─► 17.9 Social Graph & Live Activity
  │     │                 │
  │     │                 └─► 17.10 Social Side Panel (in-workspace)
  │     │
  │     ├─► 17.6 Skill Management
  │     │
  │     └─► 17.7 Chat Log Saving
  │
  └─► 17.8 GitHub OAuth (independent, can be done anytime after 17.1)
```

**Recommended build order:**
1. **17.1** — Auth scaffolding + multi-tenant gate
2. **17.2** — Snippets schema + Social context
3. **17.3** — Favorites (quick, unlocks homepage)
4. **17.4** — Homepage LiveView
5. **17.6** — Skill import/install (high user value)
6. **17.7** — Chat log saving (quick win)
7. **17.5** — Detail views, profiles, explore
8. **17.9** — Follows, live activity presence, activity feed
9. **17.10** — Social side panel in WorkspaceLive
10. **17.8** — GitHub OAuth (nice-to-have)

## Risks & Open Questions

1. **skills.sh registry API** — Does it have an API for publishing skills, or is `npx skills` the only interface? If no API, the "publish to registry" feature would need to shell out or wait for their API.

2. **Snippet versioning** — The `version` field is a simple integer bump. If we need full version history (diffing between versions), that's a bigger schema (separate `snippet_versions` table). Starting simple.

3. **Content search** — Full-text search across snippet content will want PostgreSQL `tsvector` indexes. Not in v1, but the schema supports it.

4. **Forking semantics** — A fork is a full deep copy. No upstream sync. If someone wants to "pull updates" from the original, they'd need to re-fork or manually merge. This matches GitHub gist behavior.

5. **Rate limiting** — In deployed mode, we'll eventually need rate limiting on snippet creation, fork, and API access. Not in v1.

6. **Multi-tenant data isolation** — In deployed mode, users should only see their own private snippets and all public ones. Query scoping must be airtight. The `Social` context handles this, but it needs careful testing.
