defmodule Loomkin.Tools.TeamSpawn do
  @moduledoc "Spawn a team with agents."

  @valid_roles ~w(lead researcher coder reviewer tester)

  use Jido.Action,
    name: "team_spawn",
    description:
      "Create a new agent team and spawn agents with specified roles. " <>
        "Standard roles: researcher (read-only exploration), coder (implementation), " <>
        "reviewer (code review), tester (run tests), lead (coordination). " <>
        "You can also specify custom specialist roles by description (e.g. 'database-migration-specialist'). " <>
        "You MUST provide a roles list with name and role for each agent. " <>
        "Returns a team status summary with team_id and agent list.",
    schema: [
      team_name: [type: :string, required: true, doc: "Human-readable team name"],
      roles: [type: {:list, :map}, required: true, doc: "List of %{name, role} maps. role can be a standard role or a custom specialist description"],
      project_path: [type: :string, doc: "Path to the project for agents to work on"]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  alias Loomkin.Teams.{Manager, Role}

  require Logger

  @impl true
  def run(params, context) do
    team_name = param!(params, :team_name)
    project_path = param(params, :project_path) || param(context, :project_path)
    parent_team_id = param(context, :parent_team_id)
    model = param(context, :model)

    roles = param!(params, :roles)
    spawn_from_roles(team_name, roles, project_path, parent_team_id, model)
  end

  defp spawn_from_roles(team_name, roles, project_path, parent_team_id, model) do
    {:ok, team_id} =
      if parent_team_id do
        Manager.create_sub_team(parent_team_id, "architect", name: team_name, project_path: project_path)
      else
        Manager.create_team(name: team_name, project_path: project_path)
      end

    spawn_opts =
      [project_path: project_path]
      |> then(fn opts -> if model, do: [{:model, model} | opts], else: opts end)

    results =
      Enum.map(roles, fn role_map ->
        name = Map.get(role_map, :name) || Map.get(role_map, "name")
        role = Map.get(role_map, :role) || Map.get(role_map, "role")

        case resolve_role(role) do
          {:built_in, role_atom} ->
            case Manager.spawn_agent(team_id, name, role_atom, spawn_opts) do
              {:ok, _pid} -> "  - #{name} (#{role_atom}): spawned"
              {:error, reason} -> "  - #{name} (#{role_atom}): failed - #{inspect(reason)}"
            end

          {:custom, role_desc} ->
            case Role.generate(role_desc) do
              {:ok, %Role{} = role_config} ->
                custom_opts = Keyword.put(spawn_opts, :role_config, role_config)

                case Manager.spawn_agent(team_id, name, role_config.name, custom_opts) do
                  {:ok, _pid} -> "  - #{name} (#{role_config.name}): spawned (custom)"
                  {:error, reason} -> "  - #{name} (#{role_config.name}): failed - #{inspect(reason)}"
                end

              {:error, reason} ->
                Logger.warning("Role.generate failed for '#{role_desc}': #{inspect(reason)}, falling back to :researcher")
                fallback = fuzzy_match_role(role_desc) || :researcher

                case Manager.spawn_agent(team_id, name, fallback, spawn_opts) do
                  {:ok, _pid} -> "  - #{name} (#{fallback}): spawned (fallback)"
                  {:error, reason} -> "  - #{name} (#{fallback}): failed - #{inspect(reason)}"
                end
            end
        end
      end)

    summary = """
    Team "#{team_name}" created (id: #{team_id})
    Agents:
    #{Enum.join(results, "\n")}
    """

    {:ok, %{result: String.trim(summary), team_id: team_id}}
  end

  # Resolve a role string to either a built-in role atom or a custom role description.
  # Returns {:built_in, atom} for known roles, {:custom, string} for unknown descriptions.
  defp resolve_role(role) when is_atom(role), do: {:built_in, role}

  defp resolve_role(role) when is_binary(role) do
    downcased = String.downcase(role)

    # Exact match first
    if downcased in @valid_roles do
      {:built_in, String.to_existing_atom(downcased)}
    else
      case fuzzy_match_role(role) do
        nil -> {:custom, role}
        atom -> {:built_in, atom}
      end
    end
  end

  defp resolve_role(_), do: {:built_in, :researcher}

  # Keyword-based fuzzy match for descriptive role strings.
  # Returns the best matching built-in role atom, or nil if no match.
  defp fuzzy_match_role(role) when is_binary(role) do
    downcased = String.downcase(role)

    cond do
      String.contains?(downcased, "review") -> :reviewer
      String.contains?(downcased, "test") -> :tester
      String.contains?(downcased, "code") or String.contains?(downcased, "implement") -> :coder
      String.contains?(downcased, "research") or String.contains?(downcased, "analy") or
        String.contains?(downcased, "audit") or String.contains?(downcased, "explor") or
        String.contains?(downcased, "investigat") or String.contains?(downcased, "document") -> :researcher
      String.contains?(downcased, "lead") or String.contains?(downcased, "coordinat") -> :lead
      # If the LLM sends a security/quality/architecture analysis role, map to researcher
      String.contains?(downcased, "security") or String.contains?(downcased, "quality") or
        String.contains?(downcased, "architect") or String.contains?(downcased, "coverage") -> :researcher
      true -> nil
    end
  end
end
