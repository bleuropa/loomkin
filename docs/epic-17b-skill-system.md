# Epic 17b: Skill System Wire-Up + Snippet Install Paths

## Problem Statement

The social platform (Epic 17) built a sharing layer (snippets, fork, favorite, explore) but it's disconnected from the agent runtime. Skills on disk are inert — agents never read them. `system_prompt_extra` on KinAgent is defined but never injected. Forked snippets sit in your profile but can't be "installed" into a workspace. Jido already ships `Jido.AI.Skill`, `Jido.AI.Skill.Registry`, and `Jido.AI.Skill.Prompt` — but none are wired into Loomkin.

## The Full Loop

```
AUTHORING (where things are born):
  Skill editor (markdown + frontmatter)  →  :skill snippet
  Workspace Kin panel "Publish"          →  :kin_agent snippet
  Workspace "Save Chat" button           →  :chat_log snippet
  Prompt editor (structured fields)      →  :prompt snippet

SHARING (the social layer):
  Publish → Explore page
  Fork    → copy in your profile
  Favorite → saved for later

INSTALLING (snippet → usable thing):
  :skill snippet      →  "Install" → loaded into Jido.AI.Skill.Registry → agents see it
  :kin_agent snippet  →  "Install" → creates KinAgent record → appears in Kin panel
  :prompt snippet     →  "Install" → becomes system_prompt_extra on a kin agent
  :chat_log snippet   →  (reference only, not installable)

USING (the agent runtime):
  Agent sees skill manifests in system prompt (name + description)
  Agent calls load_skill("name") tool to get full body on demand
  KinAgent.system_prompt_extra injected into agent's system prompt
```

---

## Phase 1: Make Skills Work at Runtime

**Goal:** Agents can see skills and `system_prompt_extra` actually gets injected. Smallest change that makes skills functional.

### 1.1 Start Jido.AI.Skill.Registry in Supervision Tree

**Modify:** `lib/loomkin/application.ex`

Add `Jido.AI.Skill.Registry` as a child worker before Teams.Supervisor. No config needed — it creates its ETS table on init.

**Acceptance:** Registry process alive after boot, `:ets.info(:jido_skill_registry)` returns valid table.

### 1.2 Create Skill Resolver Module

**Create:** `lib/loomkin/skills/resolver.ex`

Single entry point for collecting skills from all sources. Merges three inputs:

1. **Disk skills** — `.agents/skills/` SKILL.md files loaded via `Jido.AI.Skill.Loader`
2. **DB skills** — Snippet records with `type: :skill` converted to `Jido.AI.Skill.Spec` structs
3. **Jido registry** — any module-based skills already registered

```elixir
defmodule Loomkin.Skills.Resolver do
  @spec load_from_disk(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_from_disk(project_path)

  @spec load_from_db(User.t() | nil) :: [Spec.t()]
  def load_from_db(user)

  @spec list_manifests(String.t() | nil, User.t() | nil) :: [Spec.t()]
  def list_manifests(project_path, user)

  @spec get_body(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_body(skill_name)
end
```

- `list_manifests/2` returns lightweight metadata (name + description only)
- `get_body/1` returns full markdown body for on-demand loading
- DB snippets take precedence over disk skills with same name (user customization wins)

### 1.3 Inject Skill Manifests into Context Window

**Modify:** `lib/loomkin/session/context_window.ex`

Add `inject_skills/3` following the pattern of `inject_repo_map` and `inject_project_rules`. Uses `Jido.AI.Skill.Prompt.render(specs, include_body: false)` to produce a compact manifest section.

Wire into `build_messages/3` after `inject_project_rules`:

```elixir
system_parts = inject_project_rules(system_parts, project_path)
system_parts = inject_skills(system_parts, project_path, opts[:user])
```

Budget: 512 tokens for skill manifests (~20 skills worth of name + description).

**Acceptance:** Agent system prompt includes "You have access to the following skills: ..." with names and descriptions.

### 1.4 Create `load_skill` Tool

**Create:** `lib/loomkin/tools/load_skill.ex`

```elixir
defmodule Loomkin.Tools.LoadSkill do
  use Jido.Action,
    name: "load_skill",
    description: "Load full instructions for a named skill. Use when you need detailed guidance.",
    schema: [
      name: [type: :string, required: true, doc: "The skill name (e.g. 'elixir-expert')"]
    ]

  @impl true
  def run(%{name: name}, _context) do
    case Loomkin.Skills.Resolver.get_body(name) do
      {:ok, body} -> {:ok, %{result: body}}
      {:error, :not_found} -> {:error, "Skill '#{name}' not found"}
    end
  end
end
```

**Modify:** `lib/loomkin/tools/registry.ex` — add to `@solo_tools`.

### 1.5 Inject `system_prompt_extra` from KinAgent

**Modify:** `lib/loomkin/teams/agent.ex` — `build_loop_opts/1`

After `system_prompt = inject_keeper_index(...)`, add:

```elixir
system_prompt = maybe_inject_system_prompt_extra(system_prompt, state)
```

Looks up the KinAgent record by agent name, appends `system_prompt_extra` if present.

**Acceptance:** Create kin with `system_prompt_extra: "Always use guard clauses"` → spawn it → verify it appears in the agent's system prompt.

### 1.6 Load Disk Skills on Team Bootstrap

**Modify:** `lib/loomkin/session/session.ex` — `maybe_spawn_bootstrap_agents/1`

Before spawning agents, call `Loomkin.Skills.Resolver.load_from_disk(project_path)` to populate the Jido registry.

---

## Phase 2: Authoring, Publishing, and Install Flows

**Goal:** Users can author skills, publish kin agents from workspace, install community content into their workspace.

### 2.1 Skill Authoring Editor

**Modify:** `lib/loomkin_web/live/snippet_live.ex`

Replace the generic `:new`/`:edit` form with type-aware editors:

**`:skill` type — structured skill editor:**
- Name field (kebab-case, validated against `^[a-z0-9]+(-[a-z0-9]+)*$`)
- Description field (one line)
- Tags input
- Allowed tools (optional, comma-separated)
- Body (large markdown textarea, monospace)
- Template starters ("Start from: Code Review / Security Audit / Framework Expert / blank")

Content assembled into `%{"frontmatter" => %{...}, "body" => "..."}` before save. Validated via `Jido.AI.Skill.Loader.parse/2` to ensure valid SKILL.md format.

**`:kin_agent` type — agent config editor:**
- Role dropdown (lead, coder, researcher, etc.)
- System prompt extra textarea
- Potency slider (0-100)
- Spawn context textarea
- Model override selector

**`:prompt` type — prompt template editor:**
- System prompt textarea
- User prompt template textarea
- Variables list (add/remove)

**`:chat_log` type — read-only:**
- Only title/description/visibility/tags editable
- Messages displayed read-only

### 2.2 "Publish Kin" Button in Workspace Kin Panel

**Modify:** `lib/loomkin_web/live/kin_panel_component.ex`

Add a "Publish" or "Share" button next to each kin agent in the panel. On click:

1. Serializes KinAgent config into snippet content:
   ```elixir
   %{
     "role" => kin.role,
     "system_prompt_extra" => kin.system_prompt_extra,
     "potency" => kin.potency,
     "spawn_context" => kin.spawn_context,
     "auto_spawn" => kin.auto_spawn,
     "tool_overrides" => kin.tool_overrides,
     "budget_limit" => kin.budget_limit
   }
   ```
2. Creates a `:kin_agent` snippet with `visibility: :private`
3. Shows flash: "Kin published as snippet! Edit visibility to share it."
4. Links to the snippet edit page for title/description/visibility refinement

**Acceptance:** User creates kin in workspace → clicks "Share" → snippet appears in their profile → can set to public → others can fork it.

### 2.3 "Install to Workspace" Flows (Snippet → Usable Thing)

**Modify:** `lib/loomkin_web/live/snippet_live.ex` — `:show` action

Add an "Install" button on snippet detail pages. Behavior varies by type:

#### `:skill` → Install to Agent Runtime

```elixir
def handle_event("install_skill", %{"project_path" => path}, socket) do
  snippet = socket.assigns.snippet
  case SkillInstaller.install_to_project(snippet, path) do
    {:ok, _} ->
      Skills.Resolver.load_from_disk(path)
      {:noreply, put_flash(socket, :info, "Skill installed! Agents will see it in new sessions.")}
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Install failed: #{inspect(reason)}")}
  end
end
```

For cloud mode (no disk): mark the snippet as "installed" for this user (add an `installed_skills` table or a simple user preference). The Resolver reads installed snippet IDs and includes them in `list_manifests/2`.

#### `:kin_agent` → Create KinAgent Record

```elixir
def handle_event("install_kin", _params, socket) do
  snippet = socket.assigns.snippet
  content = snippet.content
  current_user = socket.assigns.current_scope.user

  attrs = %{
    name: Loomkin.Schemas.Snippet.slugify(snippet.title),
    display_name: snippet.title,
    role: String.to_existing_atom(content["role"]),
    system_prompt_extra: content["system_prompt_extra"],
    potency: content["potency"] || 50,
    spawn_context: content["spawn_context"],
    auto_spawn: content["auto_spawn"] || false,
    tool_overrides: content["tool_overrides"] || %{},
    budget_limit: content["budget_limit"],
    enabled: true,
    user_id: current_user.id
  }

  case Loomkin.Kin.create_kin(attrs) do
    {:ok, _kin} ->
      {:noreply, put_flash(socket, :info, "Kin agent installed! It's now in your Kin panel.")}
    {:error, changeset} ->
      {:noreply, put_flash(socket, :error, "Install failed: #{inspect(changeset.errors)}")}
  end
end
```

**Acceptance:** Fork a kin_agent snippet → click "Install" → KinAgent record created → appears in Kin panel → spawnable in sessions.

#### `:prompt` → Apply to Kin Agent

Show a dropdown of the user's existing kin agents. On select, appends the prompt content to that kin's `system_prompt_extra`:

```elixir
def handle_event("install_prompt", %{"kin_agent_id" => kin_id}, socket) do
  snippet = socket.assigns.snippet
  prompt_text = snippet.content["system_prompt"] || snippet.content["body"]
  kin = Loomkin.Kin.get_kin!(kin_id)

  existing = kin.system_prompt_extra || ""
  updated = if existing == "", do: prompt_text, else: existing <> "\n\n" <> prompt_text

  case Loomkin.Kin.update_kin(kin, %{system_prompt_extra: updated}) do
    {:ok, _} ->
      {:noreply, put_flash(socket, :info, "Prompt applied to #{kin.display_name || kin.name}!")}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to apply prompt")}
  end
end
```

**Acceptance:** Fork a prompt snippet → click "Install" → select kin agent → prompt appended to `system_prompt_extra` → agent behavior changes in next session.

### 2.4 "Save Chat" Button in WorkspaceLive

**Modify:** `lib/loomkin_web/live/workspace_live.ex`

Add a "Save Chat" button to the toolbar. Opens a modal with:
- Title (auto-suggested from session title or first user message)
- Description
- Tags
- Visibility (default: private)

On submit, calls `Social.save_chat_log(user, session, attrs)` (already exists and works).

**Acceptance:** Work with agents → click "Save Chat" → modal → creates `:chat_log` snippet → appears in profile.

### 2.5 "Import Skills from Disk" Action

**Modify:** `lib/loomkin_web/live/home_live.ex` or workspace toolbar

Button that calls `SkillImporter.import_from_disk(user, project_path)`. Imports all `.agents/skills/` SKILL.md files as `:skill` snippets. Skips duplicates by name.

---

## Phase 3: Optimization

### 3.1 Skill Manifest Caching

**Create:** `lib/loomkin/skills/cache.ex`

ETS-backed cache for `list_manifests` results per `{project_path, user_id}`. 5-minute TTL. Invalidated on skill create/update/delete/install.

### 3.2 Role-Based Skill Filtering

**Modify:** `lib/loomkin/teams/role.ex`

Skills with `allowed_tools` only shown to agents that have those tools. Uses `Jido.AI.Skill.Prompt.filter_tools/2`.

### 3.3 Skill-Aware Tool Scoping

When agent loads a skill that specifies `allowed_tools`, dynamically add those tools to the agent's active tool set for the session.

### 3.4 Cloud-Mode Skill Installation

**Create:** migration for `installed_skills` table (user_id, snippet_id, installed_at).

For cloud-hosted mode where there's no disk, "installing" a skill means adding it to this table. The Resolver includes installed skills in `list_manifests/2` alongside DB skills.

### 3.5 Snippet Content Validation

**Modify:** `lib/loomkin/schemas/snippet.ex`

Add `validate_content/1` that runs skill content through `Jido.AI.Skill.Loader.parse/2` at save time.

---

## Dependency Graph

```
Phase 1 (runtime wire-up):
  1.1 Registry in supervision tree
    └── 1.2 Resolver module
          ├── 1.3 Context window injection
          ├── 1.4 load_skill tool
          └── 1.6 Load on bootstrap
  1.5 system_prompt_extra (independent)

Phase 2 (authoring + install):
  2.1 Skill editor UI (depends on 1.2 for validation)
  2.2 Publish kin from workspace (independent)
  2.3 Install flows: skill/kin/prompt (depends on 1.2, 1.6)
  2.4 Save chat from workspace (independent)
  2.5 Import skills from disk (depends on 1.2)

Phase 3 (optimization):
  3.1 Caching (depends on 1.2)
  3.2 Role filtering (depends on 1.3)
  3.3 Tool scoping (depends on 1.4)
  3.4 Cloud-mode install table (depends on 2.3)
  3.5 Content validation (depends on 2.1)
```

## Key Jido Modules to Leverage

| Module | What we use it for |
|--------|-------------------|
| `Jido.AI.Skill.Registry` | Global skill index (ETS-backed) |
| `Jido.AI.Skill.Loader` | Parse SKILL.md files from disk |
| `Jido.AI.Skill.Spec` | Struct for skill metadata + body |
| `Jido.AI.Skill.Prompt` | `render/2` for prompt formatting, `filter_tools/2` for role matching |
| `Jido.Action` | Base for `load_skill` tool |
