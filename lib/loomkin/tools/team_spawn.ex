defmodule Loomkin.Tools.TeamSpawn do
  @moduledoc "Spawn a team with agents."

  @valid_roles ~w(lead researcher coder reviewer tester concierge orienter)

  use Jido.Action,
    name: "team_spawn",
    description:
      "Create a new agent team and spawn agents with specified roles. " <>
        "Valid roles: researcher (read-only exploration), coder (implementation), " <>
        "reviewer (code review), tester (run tests), lead (coordination). " <>
        "You MUST provide a roles list with name and role for each agent. " <>
        "Returns a team status summary with team_id and agent list.",
    schema: [
      team_name: [type: :string, required: true, doc: "Human-readable team name"],
      roles: [
        type: {:list, :map},
        required: true,
        doc:
          "List of %{name, role} maps. role must be one of: researcher, coder, reviewer, tester, lead"
      ],
      project_path: [type: :string, doc: "Path to the project for agents to work on"]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  alias Loomkin.Teams.Manager

  @impl true
  def run(params, context) do
    team_name = param!(params, :team_name)
    project_path = param(params, :project_path) || param(context, :project_path)
    parent_team_id = param(context, :parent_team_id)
    session_id = param(context, :session_id)
    model = param(context, :model)
    agent_name = param(context, :agent_name) || "architect"

    roles = param!(params, :roles)

    spawn_from_roles(
      team_name,
      roles,
      project_path,
      parent_team_id,
      session_id,
      model,
      agent_name
    )
  end

  defp spawn_from_roles(
         team_name,
         roles,
         project_path,
         parent_team_id,
         session_id,
         model,
         agent_name
       ) do
    require Logger

    Logger.info(
      "[Kin:team_spawn] team=#{team_name} roles=#{inspect(roles)} parent=#{inspect(parent_team_id)}"
    )

    {:ok, team_id} =
      if parent_team_id do
        Manager.create_sub_team(parent_team_id, agent_name,
          name: team_name,
          project_path: project_path
        )
      else
        Manager.create_team(name: team_name, project_path: project_path)
      end

    spawn_opts =
      [project_path: project_path]
      |> then(fn opts -> if session_id, do: [{:session_id, session_id} | opts], else: opts end)
      |> then(fn opts -> if model, do: [{:model, model} | opts], else: opts end)

    spawn_results =
      Enum.map(roles, fn role_map ->
        name = Map.get(role_map, :name) || Map.get(role_map, "name")
        role = Map.get(role_map, :role) || Map.get(role_map, "role")
        role_atom = resolve_role(role)

        if is_nil(role_atom) do
          {:error, name, role, "unknown role. Valid: #{Enum.join(@valid_roles, ", ")}"}
        else
          case Manager.spawn_agent(team_id, name, role_atom, spawn_opts) do
            {:ok, _pid} -> {:ok, name, role_atom}
            {:error, reason} -> {:error, name, role_atom, inspect(reason)}
          end
        end
      end)

    # Notify parent team listeners (e.g. WorkspaceLive) so they subscribe to the sub-team
    any_spawned = Enum.any?(spawn_results, &match?({:ok, _, _}, &1))

    if parent_team_id && any_spawned do
      signal =
        Loomkin.Signals.Team.ChildTeamCreated.new!(%{
          team_id: team_id,
          parent_team_id: parent_team_id
        })

      Loomkin.Signals.publish(signal)
    end

    lines =
      Enum.map(spawn_results, fn
        {:ok, name, role} -> "  - #{name} (#{role}): spawned"
        {:error, name, role, reason} -> "  - #{name} (#{role}): failed - #{reason}"
      end)

    summary = """
    Team "#{team_name}" created (id: #{team_id})
    Agents:
    #{Enum.join(lines, "\n")}
    """

    {:ok, %{result: String.trim(summary), team_id: team_id}}
  end

  # Resolve a role string to one of the valid role atoms.
  # Handles exact matches, and falls back to keyword matching for
  # descriptive strings like "Analyze code quality and patterns".
  defp resolve_role(role) when is_atom(role), do: role

  defp resolve_role(role) when is_binary(role) do
    downcased = String.downcase(role)

    # Exact match first
    if downcased in @valid_roles do
      String.to_existing_atom(downcased)
    else
      # Keyword-based fuzzy match for descriptive role strings
      cond do
        String.contains?(downcased, "review") ->
          :reviewer

        String.contains?(downcased, "test") ->
          :tester

        String.contains?(downcased, "code") or String.contains?(downcased, "implement") ->
          :coder

        String.contains?(downcased, "research") or String.contains?(downcased, "analy") or
          String.contains?(downcased, "audit") or String.contains?(downcased, "explor") or
          String.contains?(downcased, "investigat") or String.contains?(downcased, "document") ->
          :researcher

        String.contains?(downcased, "lead") or String.contains?(downcased, "coordinat") ->
          :lead

        String.contains?(downcased, "concierge") or String.contains?(downcased, "host") ->
          :concierge

        String.contains?(downcased, "orient") or String.contains?(downcased, "scanner") ->
          :orienter

        # If the LLM sends a security/quality/architecture analysis role, map to researcher
        String.contains?(downcased, "security") or String.contains?(downcased, "quality") or
          String.contains?(downcased, "architect") or String.contains?(downcased, "coverage") ->
          :researcher

        true ->
          nil
      end
    end
  end

  defp resolve_role(_), do: nil
end
