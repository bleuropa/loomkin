defmodule Loomkin.Teams.Role do
  @moduledoc """
  Defines per-role configuration for team agents: tools, system prompt, limits.

  All roles use the same user-configured model (uniform model default). Agents
  differ in their tools and system prompts, not their intelligence level. The
  `model_tier` field is kept for backward compatibility but defaults to `:default`
  for all built-in roles — meaning "use whatever the user configured."
  """

  require Logger

  defstruct [:name, :model_tier, :tools, :system_prompt, :budget_limit]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          model_tier: atom(),
          tools: [module()],
          system_prompt: String.t(),
          budget_limit: float() | nil
        }

  # Legacy tier map — kept only for backward-compatible `model_for_tier/1` calls
  # and legacy config parsing. New code should use `ModelRouter.default_model/0`.
  @legacy_tier_models %{
    grunt: "zai:glm-4.5",
    standard: "zai:glm-5",
    expert: "anthropic:claude-sonnet-4-6",
    architect: "anthropic:claude-opus-4-6"
  }

  # -- Tool groups --

  @read_only_tools [
    Loomkin.Tools.FileRead,
    Loomkin.Tools.FileSearch,
    Loomkin.Tools.ContentSearch,
    Loomkin.Tools.DirectoryList
  ]

  @decision_tools [
    Loomkin.Tools.DecisionLog,
    Loomkin.Tools.DecisionQuery
  ]

  @write_tools [
    Loomkin.Tools.FileWrite,
    Loomkin.Tools.FileEdit
  ]

  @exec_tools [
    Loomkin.Tools.Shell,
    Loomkin.Tools.Git
  ]

  @peer_tools [
    Loomkin.Tools.PeerMessage,
    Loomkin.Tools.PeerDiscovery,
    Loomkin.Tools.PeerClaimRegion,
    Loomkin.Tools.PeerReview,
    Loomkin.Tools.PeerCreateTask,
    Loomkin.Tools.PeerCompleteTask,
    Loomkin.Tools.PeerAskQuestion,
    Loomkin.Tools.PeerAnswerQuestion,
    Loomkin.Tools.PeerForwardQuestion,
    Loomkin.Tools.PeerChangeRole,
    Loomkin.Tools.ContextRetrieve,
    Loomkin.Tools.SearchKeepers,
    Loomkin.Tools.ContextOffload,
    Loomkin.Tools.AskUser
  ]

  @lead_tools [
    Loomkin.Tools.TeamSpawn,
    Loomkin.Tools.TeamAssign,
    Loomkin.Tools.TeamSmartAssign,
    Loomkin.Tools.TeamProgress,
    Loomkin.Tools.TeamDissolve
  ]

  @all_tools [
    Loomkin.Tools.FileRead,
    Loomkin.Tools.FileWrite,
    Loomkin.Tools.FileEdit,
    Loomkin.Tools.FileSearch,
    Loomkin.Tools.ContentSearch,
    Loomkin.Tools.DirectoryList,
    Loomkin.Tools.Shell,
    Loomkin.Tools.Git,
    Loomkin.Tools.DecisionLog,
    Loomkin.Tools.DecisionQuery,
    Loomkin.Tools.SubAgent,
    Loomkin.Tools.LspDiagnostics
  ] ++ @lead_tools ++ @peer_tools

  @tool_name_to_module %{
    "file_read" => Loomkin.Tools.FileRead,
    "file_write" => Loomkin.Tools.FileWrite,
    "file_edit" => Loomkin.Tools.FileEdit,
    "file_search" => Loomkin.Tools.FileSearch,
    "content_search" => Loomkin.Tools.ContentSearch,
    "directory_list" => Loomkin.Tools.DirectoryList,
    "shell" => Loomkin.Tools.Shell,
    "git" => Loomkin.Tools.Git,
    "decision_log" => Loomkin.Tools.DecisionLog,
    "decision_query" => Loomkin.Tools.DecisionQuery,
    "sub_agent" => Loomkin.Tools.SubAgent,
    "lsp_diagnostics" => Loomkin.Tools.LspDiagnostics,
    "team_spawn" => Loomkin.Tools.TeamSpawn,
    "team_assign" => Loomkin.Tools.TeamAssign,
    "team_smart_assign" => Loomkin.Tools.TeamSmartAssign,
    "team_progress" => Loomkin.Tools.TeamProgress,
    "team_dissolve" => Loomkin.Tools.TeamDissolve,
    "peer_message" => Loomkin.Tools.PeerMessage,
    "peer_discovery" => Loomkin.Tools.PeerDiscovery,
    "peer_claim_region" => Loomkin.Tools.PeerClaimRegion,
    "peer_review" => Loomkin.Tools.PeerReview,
    "peer_create_task" => Loomkin.Tools.PeerCreateTask,
    "peer_complete_task" => Loomkin.Tools.PeerCompleteTask,
    "peer_ask_question" => Loomkin.Tools.PeerAskQuestion,
    "peer_answer_question" => Loomkin.Tools.PeerAnswerQuestion,
    "peer_forward_question" => Loomkin.Tools.PeerForwardQuestion,
    "peer_change_role" => Loomkin.Tools.PeerChangeRole,
    "context_retrieve" => Loomkin.Tools.ContextRetrieve,
    "search_keepers" => Loomkin.Tools.SearchKeepers,
    "context_offload" => Loomkin.Tools.ContextOffload,
    "ask_user" => Loomkin.Tools.AskUser
  }

  # -- Shared behavioral guidance (injected into all roles) --

  @shared_behavioral_guidance """

  ## Working Principles
  - When you need multiple tools and they don't depend on each other, call them all at once rather than sequentially.
  - If your approach is blocked, don't retry the same thing — analyze why it failed and try an alternative.
  - If a task is ambiguous, ask for clarification rather than guessing. Use peer_ask_question for teammates or ask_user for the human operator.
  """

  # -- Context Mesh prompt blocks --

  @context_mesh_prompt """

  ## Context Mesh

  You have access to a shared knowledge system called the Context Mesh. It allows you to:
  - **Offload** completed work to persistent Keepers (use `context_offload` tool)
  - **Retrieve** knowledge from any Keeper (use `context_retrieve` tool)
  - **Discover** what teammates know (use `peer_discovery` tool)

  ### When to Offload
  - After completing a subtask or research topic
  - Before switching to a new topic
  - When you see a context pressure warning (>50%)

  ### When to Retrieve
  - Before starting work on a new task — check if someone already explored this
  - When answering questions — keepers may have relevant context
  - When you see a keeper notification from a teammate

  ### Available Keepers
  {keeper_index}
  """

  @context_role_guidance %{
    lead: """
    - Before decomposing tasks, check keepers for prior analysis
    - After receiving agent results, offload the synthesis to a keeper for team reference
    - Monitor team context health — if an agent seems to be re-researching, point them to keepers
    - Offload key decisions and rationale after planning phases
    """,
    researcher: """
    - Offload findings to a keeper when you complete each research subtask
    - Before starting research, query existing keepers — another agent may have already explored this
    - Broadcast key discoveries via peer_discovery so the team knows immediately
    - Your research has the most long-term value — always offload before your context fills up
    """,
    coder: """
    - Before implementing, retrieve relevant keeper context — a researcher may have mapped the area
    - After completing a significant implementation, offload your notes for the tester and reviewer
    - If you discover unexpected dependencies, broadcast via peer_discovery
    """,
    reviewer: """
    - Query keepers for the original research and design decisions before reviewing code
    - Your review feedback is valuable — offload review notes for future reference
    """,
    tester: """
    - Query keepers for implementation notes and design decisions when writing test plans
    - Offload test results and coverage analysis for the team's reference
    """
  }

  # -- Peer Communication prompt (appended to all roles) --

  @peer_communication_prompt """

  ## Peer Communication

  You are part of a team. Proactive communication makes the team effective:
  - **Before starting work**: Check if teammates have relevant context — use `peer_ask_question` to ask
  - **After completing a subtask**: Share your findings with teammates — use `peer_discovery` to broadcast or `peer_message` for a specific teammate
  - **When you find something relevant to a teammate**: Send it directly — use `peer_message`
  - **When asked a question**: Always respond promptly — use `peer_answer_question`
  - **Don't work in isolation**: If you're unsure, ask. If you learned something, share it.
  """

  @peer_role_guidance %{
    lead: """
    - Use peer_message to relay context between agents (e.g. researcher findings to coder)
    - Monitor agent progress and send nudges when agents seem stuck
    """,
    researcher: """
    - After exploring code, immediately share findings with the coder via peer_message
    - Use peer_discovery to broadcast key architectural patterns you find
    """,
    coder: """
    - Before implementing, ask the researcher for relevant findings via peer_ask_question
    - After implementing, notify the reviewer and tester via peer_message
    """,
    reviewer: """
    - After reviewing, send feedback directly to the coder via peer_message
    - Share quality concerns with the lead via peer_message if they need attention
    """,
    tester: """
    - Share test results immediately via peer_message to coder and lead
    - If tests reveal issues, use peer_message to the coder with specific failure details
    """
  }

  # -- Built-in role definitions --
  #
  # All roles use `model_tier: :default` — the uniform model default.
  # Agents are differentiated by tools and system prompts, not model intelligence.

  @built_in_role_data %{
    lead: %{
      model_tier: :default,
      tools: @all_tools,
      system_prompt: """
      You are the team lead. Your PRIMARY job is decomposition, delegation, and coordination.
      You are a manager, not an individual contributor.

      ## Core Principle
      **Never do significant research or coding yourself.** Your value is in orchestration:
      - Decompose tasks into clear subtasks and delegate to specialists
      - Relay context between agents using peer_message when one agent's output is needed by another
      - Monitor progress and unblock stuck agents
      - Synthesize results into a coherent final answer

      ## Task Decomposition
      - Break down the user's request into clear, actionable subtasks before delegating
      - Include acceptance criteria, file paths, and expected output format for each subtask
      - Assign subtasks to the most appropriate role (researcher, coder, reviewer, tester)
      - When decomposing tasks, you can use the standard roles (researcher, coder, reviewer, tester) or describe custom specialist roles. For example, instead of just 'coder', you might request 'database-migration-specialist' or 'api-integration-agent' if the task demands specific expertise.
      - Never do research or coding yourself — delegate to the researcher or coder

      ## Active Coordination
      - Use peer_message to relay findings from the researcher to the coder
      - Use peer_message to route review feedback from the reviewer back to the coder
      - When an agent completes a subtask, immediately check if it unblocks other agents
      - If an agent is stuck, investigate why, provide context, and reassign if needed

      ## Action Safety
      - Before delegating destructive or hard-to-reverse tasks, assess the blast radius
      - Prefer reversible approaches (new commits over amends, soft resets over hard)
      - Confirm with the user before actions visible to others (pushing code, creating PRs)
      """
    },
    researcher: %{
      model_tier: :default,
      tools: @read_only_tools ++ @decision_tools ++ @peer_tools,
      system_prompt: """
      You are a research agent. Your job is to explore the codebase, analyze patterns,
      and report findings to the team lead. You are read-only — never modify files.

      ## Search Strategy
      - Use file_search for finding files by name or glob pattern
      - Use content_search for finding code by content or regex
      - Search broadly first, then drill into specifics
      - Always read file contents before reporting on them — don't rely on search snippets alone

      ## Output Format
      - Reference all code with `file_path:line_number`
      - Summarize findings in bullet points, not walls of text
      - Distinguish between confirmed facts and inferences
      - Note patterns, conventions, and potential issues
      - Log important discoveries using the decision tools
      """
    },
    coder: %{
      model_tier: :default,
      tools: @read_only_tools ++ @write_tools ++ @exec_tools ++ [Loomkin.Tools.DecisionLog] ++ @peer_tools,
      system_prompt: """
      You are a coding agent. Your job is to implement changes, write code, and run commands.

      ## Core Workflow
      - ALWAYS read a file before editing it — never propose changes to code you haven't read
      - For non-trivial tasks, explore the codebase first and propose your approach before writing code
      - Make minimal, focused edits — follow the project's existing code style and patterns
      - Run the compiler and tests after making changes to verify correctness
      - If a task is unclear, ask the lead for clarification rather than guessing

      ## Avoid Over-Engineering
      - Only make changes that are directly requested or clearly necessary
      - Don't add features, refactor code, or make improvements beyond what was asked
      - Don't add docstrings, comments, or type annotations to code you didn't change
      - Don't create helpers or abstractions for one-time operations
      - Three similar lines of code is better than a premature abstraction
      - A bug fix doesn't need surrounding code cleaned up

      ## Security
      - Never introduce command injection, XSS, SQL injection, or other OWASP top 10 vulnerabilities
      - If you notice insecure code you wrote, immediately fix it
      - Prioritize writing safe, secure, and correct code

      ## Git Safety
      - Prefer creating new commits over amending existing ones
      - Stage specific files by name rather than `git add .`
      - Never force push or skip hooks (--no-verify) unless explicitly asked

      ## Error Recovery
      - If your approach is blocked, try alternative approaches rather than brute forcing
      - If a test or command fails, analyze the root cause rather than retrying blindly
      - Log significant implementation decisions using decision tools
      """
    },
    reviewer: %{
      model_tier: :default,
      tools: @read_only_tools ++ [Loomkin.Tools.Shell] ++ @decision_tools ++ @peer_tools,
      system_prompt: """
      You are a code review agent. Your job is to review code quality, find issues,
      and suggest improvements.

      ## Review Focus
      - Check for correctness, security vulnerabilities, and edge cases
      - Verify the code follows project conventions and patterns
      - Look for missing error handling and potential failure modes
      - Run the compiler and any linters to catch issues

      ## Output Format
      - Reference all findings with `file_path:line_number`
      - Categorize issues: critical (must fix), warning (should fix), suggestion (nice to have)
      - Provide specific, actionable feedback — not vague style preferences

      ## Scope Discipline
      - Don't suggest abstractions or refactors beyond the scope of the change
      - Focus on correctness and safety over style preferences
      - Log review findings using the decision tools
      """
    },
    tester: %{
      model_tier: :default,
      tools: @read_only_tools ++ [Loomkin.Tools.Shell, Loomkin.Tools.DecisionLog] ++ @peer_tools,
      system_prompt: """
      You are a testing agent. Your job is to run tests, validate changes, and report results.

      ## Test Execution
      - Run the relevant test suite to check for regressions
      - Verify that new code has adequate test coverage
      - Suggest missing test cases for edge cases and error paths
      - Use shell commands to run mix test and other validation tools

      ## Output Format
      - Report results with exact test file paths and failure line numbers
      - Include the actual error message and stacktrace, not just "test failed"
      - Summarize: total tests, passing count, failure count with details
      - If tests fail, analyze the failure output and identify root causes
      - Log test results and coverage observations using decision tools
      """
    }
  }

  @doc "Get role configuration by name."
  @spec get(atom()) :: {:ok, t()} | {:error, :unknown_role}
  def get(name) when is_atom(name) do
    case Map.fetch(@built_in_role_data, name) do
      {:ok, data} ->
        data = Map.update!(data, :system_prompt, &append_context_awareness(name, &1))
        {:ok, struct!(__MODULE__, Map.put(data, :name, name))}

      :error ->
        {:error, :unknown_role}
    end
  end

  defp append_context_awareness(role, base_prompt) do
    context_guidance = Map.get(@context_role_guidance, role, "")
    peer_guidance = Map.get(@peer_role_guidance, role, "")

    base_prompt <>
      @shared_behavioral_guidance <>
      @peer_communication_prompt <>
      "\n### Peer Communication for Your Role\n" <>
      peer_guidance <>
      "\n### Context Awareness\n" <>
      context_guidance <>
      @context_mesh_prompt
  end

  @doc """
  Get the model string for a tier (legacy).

  For the `:default` tier, delegates to `Loomkin.Teams.ModelRouter.default_model/0`.
  For legacy tier atoms (`:grunt`, `:standard`, `:expert`, `:architect`), returns
  the hardcoded model string for backward compatibility.

  New code should use `Loomkin.Teams.ModelRouter.default_model/0` directly.
  """
  @spec model_for_tier(atom()) :: String.t()
  def model_for_tier(:default) do
    Loomkin.Teams.ModelRouter.default_model()
  end

  def model_for_tier(tier) when is_atom(tier) do
    Map.get(@legacy_tier_models, tier, Loomkin.Teams.ModelRouter.default_model())
  end

  @doc "List all built-in role names."
  @spec built_in_roles() :: [atom()]
  def built_in_roles do
    Map.keys(@built_in_role_data)
  end

  # -- Tool catalog descriptions (for LLM-based role generation) --

  @tool_descriptions %{
    "file_read" => "Read the contents of a file",
    "file_write" => "Create or overwrite a file",
    "file_edit" => "Make targeted edits to an existing file",
    "file_search" => "Search for files by name or glob pattern",
    "content_search" => "Search file contents by text or regex",
    "directory_list" => "List files and directories in a path",
    "shell" => "Execute shell commands",
    "git" => "Run git operations",
    "decision_log" => "Log a decision, finding, or rationale",
    "decision_query" => "Query the decision log for past entries",
    "sub_agent" => "Spawn a short-lived sub-agent for a focused task",
    "lsp_diagnostics" => "Get LSP diagnostics (compiler warnings/errors)"
  }

  @lead_tool_names MapSet.new([
    "team_spawn",
    "team_assign",
    "team_smart_assign",
    "team_progress",
    "team_dissolve"
  ])

  @peer_tool_names [
    "peer_message",
    "peer_discovery",
    "peer_claim_region",
    "peer_review",
    "peer_create_task",
    "peer_complete_task",
    "peer_ask_question",
    "peer_answer_question",
    "peer_forward_question",
    "peer_change_role",
    "context_retrieve",
    "search_keepers",
    "context_offload",
    "ask_user"
  ]

  # Max estimated tokens for the role-specific prompt portion (chars / 4)
  @max_prompt_chars 2048 * 4

  @doc """
  Build a catalog of available tools with descriptions, grouped by category.

  Returns a map of `%{category => [%{name: String.t(), description: String.t()}]}`.
  Excludes peer tools (always included) and lead tools (never included for generated roles).
  """
  @spec build_tool_catalog() :: %{String.t() => [%{name: String.t(), description: String.t()}]}
  def build_tool_catalog do
    %{
      "read" => catalog_entries(["file_read", "file_search", "content_search", "directory_list"]),
      "write" => catalog_entries(["file_write", "file_edit"]),
      "exec" => catalog_entries(["shell", "git"]),
      "decision" => catalog_entries(["decision_log", "decision_query"]),
      "other" => catalog_entries(["sub_agent", "lsp_diagnostics"])
    }
  end

  defp catalog_entries(names) do
    Enum.map(names, fn name ->
      %{name: name, description: Map.get(@tool_descriptions, name, name)}
    end)
  end

  @doc """
  Generate a custom role spec by calling the LLM.

  Takes a task description and optional keyword options:
    - `:team_context` - additional context about the team/project (string)

  Returns `{:ok, %Role{}}` or `{:error, reason}`.

  The generated role always includes peer tools, never includes lead tools,
  and has `model_tier: :default`. The system prompt is assembled using
  `append_context_awareness/2` just like built-in roles.
  """
  @spec generate(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def generate(task_description, opts \\ []) do
    model = Loomkin.Teams.ModelRouter.default_model()
    catalog = build_tool_catalog()
    team_context = Keyword.get(opts, :team_context, "")

    catalog_text =
      catalog
      |> Enum.map(fn {category, tools} ->
        tool_lines = Enum.map_join(tools, "\n", fn t -> "  - #{t.name}: #{t.description}" end)
        "#{category}:\n#{tool_lines}"
      end)
      |> Enum.join("\n")

    team_context_block =
      if team_context != "" do
        "\n\nAdditional team context:\n#{team_context}"
      else
        ""
      end

    system_msg =
      ReqLLM.Context.system("""
      You are a role designer for an AI agent team. Given a task description, generate a \
      role specification that defines a specialist agent.

      You MUST respond with ONLY a valid JSON object (no markdown fences, no extra text) \
      with these exact keys:
      - "role_name": a short, lowercase, hyphenated name (e.g. "migration-writer", "api-tester")
      - "system_prompt": instructions for the agent (what it specializes in, how it should work). \
        Keep this focused and under 1500 characters.
      - "tools": an array of tool name strings selected from the catalog below

      ## Available Tools (select only what the role needs)

      #{catalog_text}

      Note: Peer communication tools are always included automatically. \
      Team management tools (team_spawn, team_assign, etc.) are never available for generated roles.
      """)

    user_msg =
      ReqLLM.Context.user("""
      Task description: #{task_description}#{team_context_block}

      Generate a role specification for an agent that can handle this task.
      Respond with ONLY the JSON object.
      """)

    messages = [system_msg, user_msg]

    try do
      case Loomkin.LLMRetry.with_retry([max_retries: 2], fn ->
             ReqLLM.generate_text(model, messages, [])
           end) do
        {:ok, response} ->
          text = ReqLLM.Response.classify(response).text || ""
          parse_and_validate_role(text)

        {:error, reason} ->
          Logger.error("Role.generate LLM call failed: #{inspect(reason)}")
          {:error, {:llm_error, reason}}
      end
    rescue
      e ->
        Logger.error("Role.generate raised: #{inspect(e)}")
        {:error, {:llm_error, e}}
    end
  end

  @doc false
  def parse_and_validate_role(text) do
    # Strip markdown fences if present
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/\A```(?:json)?\s*/, "")
      |> String.replace(~r/\s*```\z/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"role_name" => name, "system_prompt" => prompt, "tools" => tools}}
      when is_binary(name) and is_binary(prompt) and is_list(tools) ->
        build_validated_role(name, prompt, tools)

      {:ok, _other} ->
        {:error, :invalid_role_format}

      {:error, _decode_err} ->
        {:error, :json_parse_error}
    end
  end

  defp build_validated_role(name_str, prompt, tool_names) do
    # Validate and sanitize role name — kept as a string to avoid
    # exhausting the VM atom table from unbounded LLM output
    role_name =
      name_str
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "_")
      |> String.slice(0, 64)

    # Cap the role-specific prompt at ~2048 tokens
    capped_prompt =
      if byte_size(prompt) > @max_prompt_chars do
        Logger.warning("Role.generate: prompt truncated from #{byte_size(prompt)} to #{@max_prompt_chars} chars")
        String.slice(prompt, 0, @max_prompt_chars)
      else
        prompt
      end

    # Validate and resolve tools
    {valid_tools, invalid_tools} =
      tool_names
      |> Enum.uniq()
      |> Enum.split_with(fn name ->
        is_binary(name) and Map.has_key?(@tool_name_to_module, name) and
          not MapSet.member?(@lead_tool_names, name)
      end)

    if invalid_tools != [] do
      Logger.warning("Role.generate: dropped invalid/lead tools: #{inspect(invalid_tools)}")
    end

    # Resolve tool name strings to modules
    resolved_tool_modules =
      Enum.map(valid_tools, fn name -> Map.fetch!(@tool_name_to_module, name) end)

    # Always include peer tools, never include lead tools
    all_tool_modules =
      (resolved_tool_modules ++ @peer_tools)
      |> Enum.uniq()

    # Assemble the full prompt using append_context_awareness (same as built-in roles)
    full_prompt = append_context_awareness(role_name, capped_prompt)

    role = %__MODULE__{
      name: role_name,
      model_tier: :default,
      tools: all_tool_modules,
      system_prompt: full_prompt,
      budget_limit: nil
    }

    Logger.info("Role.generate: created role #{role_name} with tools #{inspect(valid_tools ++ @peer_tool_names)}")

    {:ok, role}
  end

  @doc "Load a custom role from a config map (e.g. from .loomkin.toml [teams.roles.*])."
  @spec from_config(atom(), map()) :: t()
  def from_config(name, config) when is_atom(name) and is_map(config) do
    base =
      case Map.fetch(@built_in_role_data, name) do
        {:ok, data} -> struct!(__MODULE__, Map.put(data, :name, name))
        :error -> %__MODULE__{name: name}
      end

    %__MODULE__{
      name: name,
      model_tier: get_config_value(config, :model_tier, base.model_tier),
      tools: resolve_tools(config, base.tools),
      system_prompt: get_config_value(config, :system_prompt, base.system_prompt),
      budget_limit: get_config_value(config, :budget_limit, base.budget_limit)
    }
  end

  # -- Helpers --

  defp get_config_value(config, key, default) do
    Map.get(config, key, Map.get(config, Atom.to_string(key), default))
  end

  defp resolve_tools(config, default) do
    case Map.get(config, :tools, Map.get(config, "tools")) do
      nil ->
        default

      tool_names when is_list(tool_names) ->
        Enum.map(tool_names, fn
          name when is_binary(name) -> Map.get(@tool_name_to_module, name, name)
          mod when is_atom(mod) -> mod
        end)
    end
  end
end
