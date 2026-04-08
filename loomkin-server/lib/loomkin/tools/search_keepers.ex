defmodule Loomkin.Tools.SearchKeepers do
  @moduledoc "Search for relevant context keepers by topic."

  require Logger

  use Jido.Action,
    name: "search_keepers",
    description:
      "Search for relevant context keepers by topic. Returns a ranked list of keepers " <>
        "with topics and relevance scores, without fetching full content. Use this to find " <>
        "which keeper to query before committing to a full context_retrieve.",
    schema: [
      team_id: [type: :string, required: true, doc: "Team ID"],
      query: [
        type: :string,
        required: true,
        doc: "Natural language query to search keeper topics"
      ]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  @impl true
  def run(params, context) do
    query = param!(params, :query)
    team_id = effective_team_id(params, context)
    results = Loomkin.Teams.ContextRetrieval.search(team_id, query)
    {:ok, %{result: format_results(results, query)}}
  end

  defp effective_team_id(params, context) do
    provided_team_id = param(params, :team_id)
    context_team_id = param(context, :team_id)
    agent_name = param(context, :agent_name)

    cond do
      is_binary(context_team_id) and context_team_id != "" and context_team_id != provided_team_id ->
        Logger.warning(
          "[Kin:search_keepers] overriding provided team_id=#{inspect(provided_team_id)} with context team_id=#{inspect(context_team_id)} agent=#{inspect(agent_name)}"
        )

        context_team_id

      is_binary(context_team_id) and context_team_id != "" ->
        context_team_id

      true ->
        param!(params, :team_id)
    end
  end

  defp format_results([], _query), do: "No keepers found matching the query."

  defp format_results(results, query) do
    header = "Found #{length(results)} keeper(s) matching \"#{query}\":\n\n"

    entries =
      Enum.map_join(results, "\n", fn keeper ->
        "- [Keeper:#{keeper.id}] topic=\"#{keeper.topic}\" source=#{keeper.source_agent} tokens=#{keeper.token_count} relevance=#{keeper.relevance}"
      end)

    header <> entries
  end
end
