defmodule Loomkin.Decisions.Pulse do
  @moduledoc "Generates pulse reports for the decision graph."

  import Ecto.Query
  alias Loomkin.Repo
  alias Loomkin.Schemas.DecisionEdge
  alias Loomkin.Schemas.DecisionNode
  alias Loomkin.Decisions.Graph

  @default_confidence_threshold 50
  @default_stale_days 7
  @cache_table :pulse_health_cache
  @default_cache_ttl_ms 5 * 60 * 1000

  def ensure_cache_table do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Invalidates the cached health score for a scope (team, session, or global when nil)."
  def invalidate_cache(scope_key \\ nil) do
    if :ets.whereis(@cache_table) != :undefined do
      :ets.delete(@cache_table, scope_key)
    end

    :ok
  end

  def generate(opts \\ []) do
    confidence_threshold =
      Keyword.get(
        opts,
        :confidence_threshold,
        config_decisions(:pulse_confidence_threshold, @default_confidence_threshold)
      )

    stale_days =
      Keyword.get(
        opts,
        :stale_days,
        config_decisions(:pulse_stale_days, @default_stale_days)
      )

    scope = scope_filters(opts)

    active_goals = Graph.active_goals(scope)
    recent_decisions = Graph.recent_decisions(10, scope)
    coverage_gaps = find_coverage_gaps(scope)
    low_confidence = find_low_confidence(confidence_threshold, scope)
    stale_nodes = find_stale_nodes(stale_days, scope)
    health_score = compute_health(Keyword.put(opts, :confidence_threshold, confidence_threshold))

    %{
      active_goals: active_goals,
      recent_decisions: recent_decisions,
      coverage_gaps: coverage_gaps,
      low_confidence: low_confidence,
      stale_nodes: stale_nodes,
      health_score: health_score,
      summary:
        build_summary(active_goals, recent_decisions, coverage_gaps, low_confidence, stale_nodes)
    }
  end

  @doc "Computes a 0-100 health score for the decision graph. Results are cached per team_id."
  def compute_health(opts \\ []) do
    scope = scope_filters(opts)
    cache_key = cache_key(scope)
    ttl = Keyword.get(opts, :cache_ttl_ms, config_cache_ttl())

    ensure_cache_table()

    case lookup_cache(cache_key, ttl) do
      {:ok, score} ->
        score

      :miss ->
        score = compute_health_uncached(scope, opts)
        :ets.insert(@cache_table, {cache_key, score, System.monotonic_time(:millisecond)})
        score
    end
  end

  defp lookup_cache(cache_key, ttl) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, score, cached_at}] ->
        now = System.monotonic_time(:millisecond)

        if now - cached_at < ttl do
          {:ok, score}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  defp compute_health_uncached(scope, opts) do
    confidence_threshold =
      Keyword.get(
        opts,
        :confidence_threshold,
        config_decisions(:pulse_confidence_threshold, @default_confidence_threshold)
      )

    gap_count = count_coverage_gaps_db(scope)
    orphan_count = count_orphans_db(scope)
    low_confidence_count = count_low_confidence_db(scope, confidence_threshold)

    100 - min(gap_count * 10, 50) - min(orphan_count * 5, 30) - min(low_confidence_count * 3, 20)
  end

  defp count_low_confidence_db(scope, threshold) do
    active_nodes_query(scope)
    |> where([n], not is_nil(n.confidence))
    |> where([n], n.confidence < ^threshold)
    |> Repo.aggregate(:count)
  end

  defp count_orphans_db(scope) do
    active_q = active_node_refs_query(scope)

    # Non-goal active nodes that have no edges (neither from nor to)
    from(n in subquery(active_q),
      as: :node,
      where: n.node_type != :goal,
      where:
        not exists(
          from(e in DecisionEdge,
            where: e.from_node_id == parent_as(:node).id or e.to_node_id == parent_as(:node).id
          )
        )
    )
    |> Repo.aggregate(:count)
  end

  defp count_coverage_gaps_db(scope) do
    active_q = active_node_refs_query(scope)

    # Goal/decision nodes that have no outgoing edge to an :action or :outcome node
    from(n in subquery(active_q),
      as: :node,
      where: n.node_type in [:goal, :decision],
      where:
        not exists(
          from(e in DecisionEdge,
            join: target in DecisionNode,
            on: target.id == e.to_node_id,
            where: e.from_node_id == parent_as(:node).id,
            where: target.node_type in [:action, :outcome]
          )
        )
    )
    |> Repo.aggregate(:count)
  end

  defp active_nodes_query(scope) do
    DecisionNode
    |> where([n], n.status == :active)
    |> maybe_apply_scope(scope)
  end

  defp active_node_refs_query(scope) do
    active_nodes_query(scope)
    |> select([n], %{id: n.id, node_type: n.node_type})
  end

  defp find_coverage_gaps(scope) do
    from(n in DecisionNode,
      as: :node,
      where: n.status == :active and n.node_type == :goal
    )
    |> maybe_apply_scope(scope)
    |> where(
      [n],
      not exists(
        from(e in DecisionEdge,
          join: target in DecisionNode,
          on: target.id == e.to_node_id,
          where: e.from_node_id == parent_as(:node).id,
          where: target.node_type in [:action, :outcome]
        )
      )
    )
    |> Repo.all()
  end

  defp find_low_confidence(threshold, scope) do
    active_nodes_query(scope)
    |> where([n], not is_nil(n.confidence))
    |> where([n], n.confidence < ^threshold)
    |> Repo.all()
  end

  defp find_stale_nodes(days, scope) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    active_nodes_query(scope)
    |> where([n], n.updated_at < ^cutoff)
    |> Repo.all()
  end

  defp build_summary(goals, decisions, gaps, low_conf, stale) do
    parts = [
      "#{length(goals)} active goal(s)",
      "#{length(decisions)} recent decision(s)",
      "#{length(gaps)} coverage gap(s)",
      "#{length(low_conf)} low-confidence node(s)",
      "#{length(stale)} stale node(s)"
    ]

    "Pulse: " <> Enum.join(parts, ", ") <> "."
  end

  defp config_decisions(key, default) do
    Loomkin.Config.get(:decisions, key) || default
  end

  defp config_cache_ttl do
    Loomkin.Config.get(:decisions, :pulse_cache_ttl_ms) || @default_cache_ttl_ms
  end

  defp scope_filters(opts) do
    team_id = Keyword.get(opts, :team_id)
    session_id = Keyword.get(opts, :session_id)

    cond do
      is_binary(team_id) and team_id != "" ->
        [team_id: team_id]

      valid_uuid?(session_id) ->
        [session_id: session_id]

      true ->
        []
    end
  end

  defp cache_key(team_id: team_id), do: team_id
  defp cache_key(session_id: session_id), do: {:session, session_id}
  defp cache_key([]), do: nil

  defp maybe_apply_scope(query, []), do: query

  defp maybe_apply_scope(query, team_id: team_id) do
    where(query, [n], fragment("? ->> 'team_id' = ?", n.metadata, ^team_id))
  end

  defp maybe_apply_scope(query, session_id: session_id) do
    where(query, [n], n.session_id == ^session_id)
  end

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_value), do: false
end
