defmodule Loomkin.Teams.ComplexityMonitor do
  @moduledoc """
  Per-team GenServer that monitors task and decision complexity and suggests
  specialist team spawns when complexity spikes.

  Periodically calculates a composite complexity score (0-100) from decision
  graph metrics, pending tasks, and collaboration health. When the score
  rises sharply above the historical average and exceeds the configured
  threshold, it broadcasts a spawn suggestion via Comms and records the
  decision in the graph.
  """

  use GenServer

  alias Loomkin.Decisions.Graph
  alias Loomkin.Decisions.Pulse
  alias Loomkin.Signals
  alias Loomkin.Signals.Extensions.Causality
  alias Loomkin.Teams.CollaborationMetrics
  alias Loomkin.Teams.Comms
  alias Loomkin.Teams.Context

  @default_check_interval_ms 60_000
  @default_threshold 60
  @default_spawn_cooldown_ms 300_000
  @max_history 10

  # --- Public API ---

  def start_link(opts) do
    team_id = Keyword.fetch!(opts, :team_id)
    GenServer.start_link(__MODULE__, opts, name: via(team_id))
  end

  @doc "Returns the current complexity score for the team."
  def get_score(team_id) do
    case find(team_id) do
      {:ok, pid} -> GenServer.call(pid, :get_score)
      :error -> 0
    end
  end

  @doc "Returns the complexity trend: `:rising`, `:stable`, or `:falling`."
  def get_trend(team_id) do
    case find(team_id) do
      {:ok, pid} -> GenServer.call(pid, :get_trend)
      :error -> :stable
    end
  end

  @doc "Returns the list of historical complexity snapshots."
  def get_history(team_id) do
    case find(team_id) do
      {:ok, pid} -> GenServer.call(pid, :get_history)
      :error -> []
    end
  end

  @doc "Record an external event that may affect complexity."
  def record_event(team_id, event_type) do
    case find(team_id) do
      {:ok, pid} -> GenServer.cast(pid, {:record_event, event_type})
      :error -> :ok
    end
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    team_id = Keyword.fetch!(opts, :team_id)
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval_ms)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    spawn_cooldown = Keyword.get(opts, :spawn_cooldown, @default_spawn_cooldown_ms)

    Signals.subscribe("team.conflict.*")
    Signals.subscribe("team.task.*")
    Signals.subscribe("decision.*")

    now = System.monotonic_time(:millisecond)

    state = %{
      team_id: team_id,
      check_interval: check_interval,
      scores: [],
      threshold: threshold,
      spawn_cooldown: spawn_cooldown,
      last_spawn_suggested_at: now - spawn_cooldown - 1,
      pending_events: %{
        conflicts: 0,
        debates: 0,
        tasks_created: 0
      }
    }

    schedule_check(check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_score, _from, state) do
    score = calculate_score(state)
    {:reply, score, state}
  end

  def handle_call(:get_trend, _from, state) do
    {:reply, compute_trend(state.scores), state}
  end

  def handle_call(:get_history, _from, state) do
    {:reply, state.scores, state}
  end

  @impl true
  def handle_cast({:record_event, event_type}, state) do
    state = increment_event(state, event_type)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_complexity, state) do
    score = calculate_score(state)

    # Check spawn suggestion BEFORE adding new score to history,
    # so the historical average reflects only prior scores.
    state = maybe_suggest_spawn(state, score)

    scores = Enum.take([score | state.scores], @max_history)
    state = %{state | scores: scores}

    # Reset pending event counters after check
    state = %{state | pending_events: %{conflicts: 0, debates: 0, tasks_created: 0}}

    schedule_check(state.check_interval)
    {:noreply, state}
  end

  # Unwrap signal bus delivery tuples
  def handle_info({:signal, %Jido.Signal{} = sig}, state) do
    if signal_for_team?(sig, state.team_id) do
      handle_info(sig, state)
    else
      {:noreply, state}
    end
  end

  def handle_info(%Jido.Signal{type: "team.conflict.detected"}, state) do
    {:noreply, increment_event(state, :conflict)}
  end

  def handle_info(%Jido.Signal{type: "team.task." <> _}, state) do
    {:noreply, increment_event(state, :task_created)}
  end

  def handle_info(%Jido.Signal{type: "decision." <> _sub, data: data}, state) do
    # Count debate-like decisions (options with multiple rounds)
    node = Map.get(data, :node)

    if node && Map.get(node, :node_type) in [:option, :revisit] do
      {:noreply, increment_event(state, :debate)}
    else
      {:noreply, state}
    end
  end

  # Catch-all
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp via(team_id) do
    {:via, Registry, {Loomkin.Teams.AgentRegistry, {:complexity_monitor, team_id}}}
  end

  defp find(team_id) do
    case Registry.lookup(Loomkin.Teams.AgentRegistry, {:complexity_monitor, team_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp calculate_score(state) do
    team_id = state.team_id

    # High-confidence decision options (>= 75): weight 20
    high_confidence_score =
      Graph.list_nodes(team_id: team_id, node_type: :option, status: :active)
      |> Enum.count(fn node -> node.confidence != nil and node.confidence >= 75 end)
      |> min(5)
      |> Kernel.*(4)

    # Long debates (> 2 rounds) via pending events: weight 15
    debate_score = min(state.pending_events.debates, 3) * 5

    # Recent conflicts: weight 25
    collab_metrics = CollaborationMetrics.get_metrics(team_id)
    conflict_count = collab_metrics.conflict_count + state.pending_events.conflicts
    conflict_score = min(conflict_count, 5) * 5

    # Pending unresolved tasks: weight 10
    pending_tasks = Context.list_cached_tasks(team_id)
    pending_count = Enum.count(pending_tasks, fn t -> t.status in [:pending, :assigned] end)
    task_score = min(pending_count, 5) * 2

    # Decision graph health (inverted — low health = high complexity): weight 30
    graph_health = Pulse.compute_health(team_id: team_id)
    graph_complexity = div(max(0, 100 - graph_health) * 30, 100)

    score = high_confidence_score + debate_score + conflict_score + task_score + graph_complexity
    min(score, 100)
  end

  defp compute_trend(scores) do
    case scores do
      [latest, previous | _] when latest > previous + 10 -> :rising
      [latest, previous | _] when latest < previous - 10 -> :falling
      _ -> :stable
    end
  end

  defp historical_avg(scores) do
    case scores do
      [] -> 0
      list -> div(Enum.sum(list), length(list))
    end
  end

  defp maybe_suggest_spawn(state, score) do
    avg = historical_avg(state.scores)
    now = System.monotonic_time(:millisecond)
    cooldown_elapsed = now - state.last_spawn_suggested_at > state.spawn_cooldown

    if score >= avg + 25 and score > state.threshold and cooldown_elapsed do
      drivers = identify_drivers(state)
      specialist_type = recommend_specialist(drivers)
      reason = "complexity spike: score #{score} vs avg #{avg}, drivers: #{inspect(drivers)}"

      Comms.broadcast(state.team_id, {:consider_team_spawn, specialist_type, reason})

      publish_threshold_signal(state.team_id, score)
      publish_spawn_suggested_signal(state.team_id, specialist_type, reason, score)
      record_decision(state.team_id, specialist_type, score, drivers)

      %{state | last_spawn_suggested_at: now}
    else
      state
    end
  end

  defp identify_drivers(state) do
    drivers = []

    collab_metrics = CollaborationMetrics.get_metrics(state.team_id)

    drivers =
      if collab_metrics.conflict_count + state.pending_events.conflicts > 0 do
        [:conflicts | drivers]
      else
        drivers
      end

    pending_tasks = Context.list_cached_tasks(state.team_id)
    pending_count = Enum.count(pending_tasks, fn t -> t.status in [:pending, :assigned] end)

    drivers =
      if pending_count > 3 do
        [:pending_tasks | drivers]
      else
        drivers
      end

    drivers =
      if state.pending_events.debates > 2 do
        [:long_debates | drivers]
      else
        drivers
      end

    if drivers == [], do: [:general_complexity], else: drivers
  end

  defp recommend_specialist(drivers) do
    cond do
      :conflicts in drivers -> "mediator"
      :pending_tasks in drivers -> "executor"
      :long_debates in drivers -> "analyst"
      true -> "generalist"
    end
  end

  defp increment_event(state, :conflict) do
    update_in(state.pending_events.conflicts, &(&1 + 1))
  end

  defp increment_event(state, :debate) do
    update_in(state.pending_events.debates, &(&1 + 1))
  end

  defp increment_event(state, :task_created) do
    update_in(state.pending_events.tasks_created, &(&1 + 1))
  end

  defp increment_event(state, _), do: state

  defp schedule_check(interval) do
    Process.send_after(self(), :check_complexity, interval)
  end

  defp publish_threshold_signal(team_id, score) do
    Loomkin.Signals.Complexity.ThresholdReached.new!(%{
      team_id: team_id,
      complexity_score: score
    })
    |> Causality.attach(team_id: team_id)
    |> Signals.publish()
  end

  defp publish_spawn_suggested_signal(team_id, specialist_type, reason, score) do
    Loomkin.Signals.Complexity.SpawnSuggested.new!(%{
      team_id: team_id,
      specialist_type: specialist_type,
      reason: reason,
      complexity_score: score
    })
    |> Causality.attach(team_id: team_id)
    |> Signals.publish()
  end

  defp record_decision(team_id, specialist_type, score, drivers) do
    Graph.add_node(%{
      node_type: :goal,
      title: "Auto-spawn #{specialist_type} specialist team",
      status: :active,
      metadata: %{
        "team_id" => team_id,
        "complexity_score" => score,
        "trigger_drivers" => Enum.map(drivers, &to_string/1),
        "source" => "complexity_monitor"
      }
    })

    Enum.each(drivers, fn driver ->
      Graph.add_node(%{
        node_type: :observation,
        title: "Complexity driver: #{driver}",
        status: :active,
        metadata: %{
          "team_id" => team_id,
          "driver" => to_string(driver),
          "source" => "complexity_monitor"
        }
      })
    end)
  end

  defp signal_for_team?(sig, team_id) do
    signal_team_id =
      get_in(sig.data, [:team_id]) ||
        get_in(sig, [Access.key(:extensions, %{}), "loomkin", "team_id"])

    signal_team_id == nil or signal_team_id == team_id
  end
end
