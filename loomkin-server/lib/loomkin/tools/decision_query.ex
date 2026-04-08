defmodule Loomkin.Tools.DecisionQuery do
  @moduledoc "Tool for querying the decision graph."

  use Jido.Action,
    name: "decision_query",
    description:
      "Query the decision graph for active goals, recent decisions, pulse reports, or search by keyword",
    schema: [
      query_type: [
        type: :string,
        required: true,
        doc: "Type of query to run (active_goals, recent_decisions, pulse, search)"
      ],
      search_term: [type: :string, doc: "Search term for 'search' query type"],
      limit: [type: :integer, doc: "Maximum results to return (default 10)"]
    ]

  import Ecto.Query
  import Loomkin.Tool, only: [param!: 2, param: 2, param: 3]

  alias Loomkin.Decisions.Graph
  alias Loomkin.Decisions.Pulse
  alias Loomkin.Schemas.DecisionNode

  @impl true
  def run(params, context) do
    query_type = param!(params, :query_type)
    limit = param(params, :limit, 10)
    scope = scope_filters(context)

    case query_type do
      "active_goals" ->
        goals = Graph.active_goals(scope)
        {:ok, %{result: format_nodes("Active Goals", goals)}}

      "recent_decisions" ->
        decisions = Graph.recent_decisions(limit, scope)
        {:ok, %{result: format_nodes("Recent Decisions", decisions)}}

      "pulse" ->
        report = Pulse.generate(scope)
        {:ok, %{result: "#{report.summary} Health: #{report.health_score}/100."}}

      "search" ->
        search_term = param(params, :search_term, "")
        results = search_nodes(search_term, limit, scope)
        {:ok, %{result: format_nodes("Search Results for '#{search_term}'", results)}}

      other ->
        {:error,
         "Unknown query_type '#{other}'. Valid types: active_goals, recent_decisions, pulse, search"}
    end
  end

  defp search_nodes(term, limit, scope) do
    pattern = "%#{term}%"

    DecisionNode
    |> maybe_apply_scope(scope)
    |> where(
      [n],
      ilike(n.title, ^pattern) or ilike(fragment("coalesce(?, '')", n.description), ^pattern)
    )
    |> limit(^limit)
    |> order_by([n], desc: n.inserted_at)
    |> Loomkin.Repo.all()
  end

  defp scope_filters(context) do
    team_id = param(context, :team_id)
    session_id = param(context, :session_id)

    cond do
      is_binary(team_id) and team_id != "" ->
        [team_id: team_id]

      valid_uuid?(session_id) ->
        [session_id: session_id]

      true ->
        []
    end
  end

  defp maybe_apply_scope(query, []), do: query

  defp maybe_apply_scope(query, team_id: team_id) do
    where(query, [n], fragment("? ->> 'team_id' = ?", n.metadata, ^team_id))
  end

  defp maybe_apply_scope(query, session_id: session_id) do
    where(query, [n], n.session_id == ^session_id)
  end

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_value), do: false

  defp format_nodes(heading, []) do
    "#{heading}: None found."
  end

  defp format_nodes(heading, nodes) do
    items =
      Enum.map_join(nodes, "\n", fn n ->
        conf = if n.confidence, do: " (confidence: #{n.confidence}%)", else: ""
        "- [#{n.node_type}] #{n.title}#{conf} (#{n.status}, id: #{n.id})"
      end)

    "#{heading}:\n#{items}"
  end
end
