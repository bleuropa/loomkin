# Testing Patterns

**Analysis Date:** 2026-03-07

## Test Framework

**Runner:**
- ExUnit (Elixir standard testing framework)
- Version: Built into Elixir 1.18+
- Config: `test/test_helper.exs`

**Assertion Library:**
- ExUnit's built-in assertions (`assert`, `refute`, `assert_receive`, `assert_received`)

**Run Commands:**
```bash
mix test              # Run all tests
mix test --seed 0    # Run tests with deterministic seed
mix test path/to/test_file.exs  # Run specific file
mix test path/to/test_file.exs:42  # Run specific line
make test  # Make target for convenience
```

**Test Configuration:**
- Database sandbox mode: `Ecto.Adapters.SQL.Sandbox.mode(Loomkin.Repo, :manual)`
- Excluded test tags by default: `:llm_dependent` (requires external API state)
- Run excluded tests: `mix test --include llm_dependent`

## Test File Organization

**Location:**
- Co-located in `test/` directory matching `lib/` structure
- Pattern: `lib/loomkin/tools/file_read.ex` → `test/loomkin/tools/file_read_test.exs`

**Naming:**
- File naming: `{module_name}_test.exs`
- Module naming: `Loomkin.Tools.FileRead` → `defmodule Loomkin.Tools.FileReadTest do`

**Directory Structure:**
```
test/
├── loomkin/          # Mirrors lib/loomkin/
│   ├── tools/
│   │   ├── file_read_test.exs
│   │   ├── registry_test.exs
│   │   └── ...
│   ├── auth/
│   │   └── oauth_server_test.exs
│   └── ...
├── support/          # Test helpers and fixtures
│   ├── data_case.ex
│   ├── conn_case.ex
│   └── hooks/
└── test_helper.exs   # Test setup and configuration
```

## Test Structure

**Basic Test Pattern:**
```elixir
defmodule Loomkin.Tools.FileReadTest do
  use ExUnit.Case, async: true

  alias Loomkin.Tools.FileRead

  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    # Create a sample file with known content
    file = Path.join(tmp_dir, "sample.txt")
    File.write!(file, "test content")
    %{project_path: tmp_dir, sample_file: file}
  end

  test "action metadata is correct" do
    assert FileRead.name() == "file_read"
    assert is_binary(FileRead.description())
  end

  @tag :tmp_dir
  test "reads entire file with line numbers", %{project_path: proj} do
    params = %{"file_path" => "sample.txt"}
    assert {:ok, %{result: result}} = FileRead.run(params, %{project_path: proj})
    assert result =~ "Line 1"
  end
end
```

**Describe Blocks:**
- Group related tests using `describe/2`:
  ```elixir
  describe "start_flow/2" do
    test "returns {:ok, url, :paste_back} for anthropic" do
      ...
    end

    test "returns error for unconfigured provider" do
      ...
    end
  end
  ```
- Improves readability and test output organization
- Examples: `test/loomkin/auth/oauth_server_test.exs`, `test/loomkin/teams/agent_test.exs`

**Test Tags:**
- `@tag :tmp_dir` - Enables temporary directory fixture (`%{tmp_dir: tmp_dir}`)
- `@tag :async` - `async: true` in `use ExUnit.Case` allows concurrent test execution
- `@tag :requires_google_config` - Skip if Google OAuth not configured
- `@tag :llm_dependent` - Excluded by default, requires external API state
- Custom tags define test categories: `test "...", %{config} do`

## Test Cases (CaseTemplates)

**DataCase (for database tests):**
- Location: `test/support/data_case.ex`
- Usage: `use Loomkin.DataCase`
- Provides: Ecto sandbox per test, database transaction isolation
- Imports: `Ecto`, `Ecto.Changeset`, `Ecto.Query`, `Loomkin.DataCase`
- Sets up: Sandbox owner, cleanup on_exit

**ConnCase (for controller/LiveView tests):**
- Location: `test/support/conn_case.ex`
- Usage: `use LoomkinWeb.ConnCase`
- Provides: HTTP connection, Phoenix testing utilities
- Imports: `Plug.Conn`, `Phoenix.ConnTest`, `Phoenix.LiveViewTest`
- Sets up: ETS sessions table, endpoint process, database sandbox

## Fixtures and Test Data

**Temporary Directory Fixture:**
- Tag: `@tag :tmp_dir`
- ExUnit automatically creates temporary directory for test
- Accessed via `%{tmp_dir: tmp_dir}` in test function
- Files written to `tmp_dir` are cleaned up after test
- Example use: Tool tests that read/write files

**Setup Helpers:**
- Use `setup/1` or `setup_all/1` to prepare test data
- Pattern from `file_read_test.exs`:
  ```elixir
  @tag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    file = Path.join(tmp_dir, "sample.txt")
    content = 1..20 |> Enum.map(&"Line #{&1}") |> Enum.join("\n")
    File.write!(file, content)
    %{project_path: tmp_dir, sample_file: file}
  end
  ```
- Setup runs before each test; `setup_all` runs once for suite
- Return `:ok` or a map to pass data to test

**Database Fixtures:**
- Not extensively used; tests create data directly
- Can use Repo.insert! for complex setup
- Example: `%{user: Loomkin.Repo.insert!(%User{})}`

## Mocking Strategy

**Framework:** Mox (for behaviour mocking)
- Declared in `test_helper.exs`: `Mox.defmock(Loomkin.MockAdapter, for: Loomkin.Channels.Adapter)`
- Only used for adapter/behaviour tests (channels, providers)

**Real Database Testing:**
- NO mocks for Ecto
- Tests use real database in sandbox transaction mode
- Each test gets isolated transaction
- Sandbox ensures tests don't interfere with each other
- Faster feedback on real database constraints/behavior

**What to Mock:**
- External APIs: HTTP clients, channel adapters (Telegex, Nostrum)
- Behaviours: Things that shouldn't run in tests
- Example mocks from codebase: `Loomkin.MockAdapter`, `Loomkin.MockTelegex`, `Loomkin.MockNostrumApi`

**What NOT to Mock:**
- Ecto operations (use real database)
- Module functions (prefer real implementations)
- Internal business logic (test the real behavior)

**Mocking Pattern:**
```elixir
Mox.expect(Loomkin.MockAdapter, :send_message, fn _msg -> :ok end)
```

## Assertion Patterns

**Basic Assertions:**
```elixir
assert value == expected         # Equality
assert is_binary(value)          # Type check
assert value =~ "pattern"        # String contains
refute condition                 # Not true
```

**Pattern Matching in Assertions:**
```elixir
# Match structure and bind values
assert {:ok, %{result: result}} = FileRead.run(params, context)
assert result =~ "expected text"

# Pattern with guard
assert {:ok, %Req.Response{status: status}} when status in 200..299 <- response
```

**Error Assertions:**
```elixir
assert {:error, msg} = FileRead.run(params, context)
assert msg =~ "File not found"
```

**Received Messages (for async/GenServer tests):**
```elixir
# Wait for message and pattern match
assert_receive {:signal, ^provider, ^message}, timeout_ms
assert_received {:telemetry_event, [:loomkin, :llm, :request, :start], _, _}
```

**Truthiness:**
```elixir
assert Process.alive?(pid)
refute OAuthServer.flow_active?(:openai)
```

## Test Types

**Unit Tests:**
- Focus: Single function or module
- Scope: Test one behavior in isolation
- Example: `test "reads file with offset and limit"`
- Pattern: Call function, assert result
- Location: `test/loomkin/tools/`, `test/loomkin/auth/`

**Integration Tests:**
- Focus: Multiple modules working together
- Scope: Real database, GenServer communication, API interactions
- Example: `test "agent loads role config tools"` (queries role config, verifies state)
- Pattern: Spawn process, send messages, verify state changes
- Note: Tests use `async: false` if they depend on singleton GenServers

**Database Tests:**
- Focus: Schema validations, queries, changesets
- Pattern: Use `Loomkin.DataCase`
- Example: Create record, verify constraints, test queries
- Transaction isolation prevents test interference

**E2E Tests:**
- Not extensively used
- Use case: LiveView components, full request/response cycles
- Pattern: Use `LoomkinWeb.ConnCase`, `Phoenix.LiveViewTest` utilities
- Example: Not found in current codebase but possible

## Async Testing

**Async Safe:**
- Use `async: true` for tests with no shared state
- Tools tests: `use ExUnit.Case, async: true`
- Allows concurrent execution, faster test suite

**Async Unsafe:**
- Use `async: false` for singleton GenServers or shared resources
- OAuth tests: `use ExUnit.Case, async: false` (shares OAuthServer process)
- Database tests: Sandbox handles isolation automatically

## Coverage

**Requirements:** None enforced (not required by CI)

**View Coverage:**
```bash
# No built-in coverage target currently; could be added with Excoveralls
```

## Common Patterns

**Temporary File Testing:**
```elixir
@tag :tmp_dir
test "reads entire file", %{project_path: proj} do
  params = %{"file_path" => "sample.txt"}
  {:ok, %{result: result}} = FileRead.run(params, %{project_path: proj})
  assert result =~ "Line 1"
end
```

**Process Registration Testing (GenServer):**
```elixir
defp start_agent(overrides \\ []) do
  team_id = Keyword.get(overrides, :team_id, unique_team_id())
  opts = [team_id: team_id, name: "agent"] |> Keyword.merge(overrides)
  {:ok, pid} = start_supervised({Agent, opts}, id: {team_id, name})
  %{pid: pid, team_id: team_id}
end

test "agent registers in registry" do
  %{pid: pid, team_id: team_id} = start_agent()
  assert [{^pid, meta}] = Registry.lookup(Loomkin.Teams.AgentRegistry, {team_id, name})
  assert meta.role == :coder
end
```

**Error Flow Testing:**
```elixir
@tag :tmp_dir
test "rejects path traversal", %{project_path: proj} do
  params = %{"file_path" => "../../etc/passwd"}
  assert {:error, msg} = FileRead.run(params, %{project_path: proj})
  assert msg =~ "outside the project directory"
end
```

**Describe Block Organization:**
```elixir
describe "start_flow/2" do
  test "returns URL for known provider" do
    ...
  end

  test "returns error for unconfigured provider" do
    ...
  end
end
```

## Pre-commit Validation

**Lefthook Integration:**
- Pre-commit hook runs formatting check before commit
- Command: `mix format --check-formatted`
- Blocks commit if formatting fails
- Run `mix format` to fix

**Running Tests Before Push:**
- Not automated; developer responsibility
- Recommended: `mix test` before `git push`
- CI will catch failures on PR

---

*Testing analysis: 2026-03-07*
