# Coding Conventions

**Analysis Date:** 2026-03-07

## Language & Environment

**Primary Language:** Elixir 1.18+
- Compiled to BEAM VM (Erlang/OTP 27+)
- Used throughout backend, business logic, and all core systems

## Naming Patterns

**Files:**
- Snake case: `file_read.ex`, `oauth_server.ex`, `project_rules.ex`
- Modules correspond to file names: `lib/loomkin/tools/file_read.ex` → `Loomkin.Tools.FileRead`
- Test files mirror source structure: `test/loomkin/tools/file_read_test.exs`
- Multiple files per directory organized by responsibility (e.g., `lib/loomkin/tools/`, `lib/loomkin/teams/`)

**Functions:**
- Snake case: `start_link/1`, `safe_path!/2`, `stream_text/3`
- Private functions prefixed with `defp`
- Predicates end with `?`: `flow_active?/1`, `outside_project?/2`
- Functions that raise errors end with `!`: `safe_path!/2`, `param!/2`

**Variables:**
- Snake case: `team_id`, `project_path`, `flow_type`
- Single letter for generic iteration: `i`, `k`, `v` in Enum operations
- Underscore prefix for unused parameters: `{_ok, value}` or `_default = nil`

**Modules:**
- PascalCase for all modules
- Nested under organizational hierarchy: `Loomkin.Teams.Agent`, `Loomkin.Tools.FileRead`
- Single file per module (no multiple modules in same file)

**Atoms/Keywords:**
- Lowercase atoms for configuration keys: `:async`, `:tmp_dir`, `:requires_google_config`
- Lowercase for module names in Elixir: `:anthropic`, `:google`, `:openai`

## Code Style

**Formatting:**
- Tool: `mix format` (configured via `.formatter.exs`)
- Must run before every commit
- Pre-commit hook enforces this via `lefthook`
- Configuration imports: `[import_deps: [:ecto, :ecto_sql, :phoenix], plugins: [Phoenix.LiveView.HTMLFormatter]]`
- Editor support: Enable format-on-save if available

**Linting:**
- Tool: Credo (via `mix credo`)
- Config: `.credo.exs`
- Many checks are disabled for backward compatibility with pre-existing code patterns
- Not enforced as hard requirement but available for code quality inspection

**Pattern Matching:**
- Prefer pattern matching over conditional logic
- Use `case`, `cond`, and `with` extensively for control flow
- Destructure function parameters where possible: `%{role: role, tools: tools}`

**Functional Style:**
- Favor immutability and pipeline operations
- Use `|>` for chaining transformations
- Use `Enum` module functions over manual recursion
- Use `with` for sequential operations with error handling

## Import Organization

**Order (top to bottom):**
1. Standard library imports (`use`, framework modules)
2. External library imports
3. Internal module imports (same application)
4. Module attributes and constants

**Example from source:**
```elixir
defmodule Loomkin.Tools.FileRead do
  use Jido.Action, [...]  # Framework setup

  import Loomkin.Tool, only: [safe_path!: 2, param!: 2]  # Internal helpers
```

**Path Aliases:**
- Do NOT use bare module names; use full qualified names
- Example: `Loomkin.Tools.Registry.find("file_read")` not `Registry.find(...)`
- Aliases are used for readability in large modules: `alias Loomkin.Teams.Agent`
- Organize aliases alphabetically

## Error Handling

**Patterns:**
- Return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Use `with` for sequential operations that can fail:
  ```elixir
  with {:ok, context} <- ReqLLM.Context.normalize(messages, opts),
       {:ok, request} <- provider_module.prepare_request(:chat, model, messages, opts),
       {:ok, %Req.Response{status: status}} when status in 200..299 <- Req.request(request) do
    {:ok, body}
  else
    {:error, error} -> {:error, error}
  end
  ```
- Raise errors for validation failures that indicate programmer error: `raise ArgumentError, "..."` (see `safe_path!/2`)
- Return error tuples for runtime failures users should handle

**Error Messages:**
- Include context: `"File not found: #{full_path}"` not just `"File not found"`
- Include next steps when applicable: `"Use directory_list with path: #{rel_path}"`
- Lowercase and no ending period in error message strings

## Documentation

**Module Documentation (@moduledoc):**
- All public modules have `@moduledoc` with brief description
- Can include how/why the module exists
- Example:
  ```elixir
  @moduledoc "Registry of all available Loomkin tools."
  @moduledoc """
  GenServer representing a single agent within a team. Every Loomkin conversation
  runs through a Teams.Agent — even solo sessions are a team of one.
  """
  ```

**Function Documentation (@doc and @spec):**
- Public functions include `@doc` and `@spec`
- `@spec` must be present before public API functions
- Format: `@spec function_name(types) :: return_type`
- Example from registry.ex:
  ```elixir
  @doc "Finds a tool module by its string name (e.g. \"file_read\")."
  @spec find(String.t()) :: {:ok, module()} | {:error, String.t()}
  def find(name) when is_binary(name) do
  ```

**Private Functions:**
- Use `@doc false` to hide private functions from docs if needed
- Or omit @doc entirely for truly private implementation details
- Can include inline comments for complex logic

**Comments:**
- Use sparingly; code should be self-documenting through clear naming
- Comments explain *why*, not *what*: The code shows what, comments explain the business reason
- Example: `# Bypass safe_path! for permitted external reads (approved via permission system)`
- TODO/FIXME comments acceptable for known issues, but kept minimal

## Function Design

**Size Guidelines:**
- Functions should fit on one screen (50-80 lines is a reasonable limit)
- Large functions indicate logic that should be extracted to helpers
- Recursive functions should be separated into public/private pairs

**Parameters:**
- Keep function arity reasonable (3-4 parameters typical)
- Use maps for configuration/options to avoid parameter explosion
- Use `keyword()` lists for options: `def execute(tool, params, context, opts \\ [])`

**Return Values:**
- Always return tagged tuples for operations that can fail: `{:ok, value}` or `{:error, reason}`
- Functions with `!` suffix may raise exceptions
- Functions returning booleans end with `?`

## Module Design

**Exports:**
- All public functions are listed in order at top of module (after @moduledoc and @doc blocks)
- Use `@impl` attribute when implementing behaviour callbacks
- Keep implementation details private with `defp`

**Barrel Files:**
- Not used extensively; modules import what they need directly
- Each module is focused and doesn't re-export other modules

**Module Organization:**
- Group related functions logically
- Public API functions first (marked with `@doc`, `@spec`)
- Helper functions follow
- Behaviour implementations (marked with `@impl true`) grouped together

## Schema and Struct Design

**Defstruct Usage:**
- Use for data representation in GenServers and processes
- Include all fields with default values: `defstruct [field: default_value, ...]`
- Example from Teams.Agent:
  ```elixir
  defstruct [
    :team_id,
    :session_id,
    :name,
    tools: [],
    messages: [],
    cost_usd: 0.0
  ]
  ```

**Changeset Pattern:**
- Use Ecto changesets for database operations
- Cast and validate explicitly in changeset functions
- Never trust user input directly

## Testing Philosophy

- Real database, no mocks for Ecto (see TESTING.md for details)
- Tests should read like specifications
- Test names are descriptive: `test "reads file with offset and limit"`
- One logical assertion per test when possible

---

*Convention analysis: 2026-03-07*
