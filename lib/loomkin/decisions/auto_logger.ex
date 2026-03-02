defmodule Loomkin.Decisions.AutoLogger do
  @moduledoc "Per-team GenServer that subscribes to team PubSub events and writes decision graph nodes."

  use GenServer

  require Logger

  alias Loomkin.Decisions.Graph
  alias Loomkin.Teams.Tasks

  @pubsub Loomkin.PubSub

  # --- Public API ---

  def start_link(opts) do
    team_id = Keyword.fetch!(opts, :team_id)
    GenServer.start_link(__MODULE__, opts, name: via(team_id))
  end

  defp via(team_id) do
    {:via, Registry, {Loomkin.Teams.AgentRegistry, {:auto_logger, team_id}}}
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    team_id = Keyword.fetch!(opts, :team_id)

    Phoenix.PubSub.subscribe(@pubsub, "team:#{team_id}")
    Phoenix.PubSub.subscribe(@pubsub, "team:#{team_id}:tasks")

    state = %{
      team_id: team_id,
      seen_agents: MapSet.new(),
      # Map of task_id => node_id for linking task action → outcome edges
      task_nodes: %{}
    }

    Logger.info("[AutoLogger] Started for team #{team_id}")
    {:ok, state}
  end

  # Agent joins (first time only)
  @impl true
  def handle_info({:agent_status, name, :working}, state) do
    if MapSet.member?(state.seen_agents, name) do
      {:noreply, state}
    else
      state = %{state | seen_agents: MapSet.put(state.seen_agents, name)}

      log_node(state, %{
        node_type: :action,
        title: "Agent #{name} joined team",
        agent_name: to_string(name)
      })

      {:noreply, state}
    end
  end

  # Ignore subsequent agent_status events
  def handle_info({:agent_status, _name, _status}, state) do
    {:noreply, state}
  end

  # Task assigned
  def handle_info({:task_assigned, task_id, agent_name}, state) do
    title = task_title(task_id)

    case log_node(state, %{
           node_type: :action,
           title: "Task assigned: #{title} → #{agent_name}",
           agent_name: to_string(agent_name),
           metadata: base_metadata(state, %{"task_id" => task_id})
         }) do
      {:ok, node} ->
        state = put_in(state.task_nodes[task_id], node.id)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Task completed
  def handle_info({:task_completed, task_id, owner, _result}, state) do
    title = task_title(task_id)

    {:ok, node} =
      log_node(state, %{
        node_type: :outcome,
        title: "Completed: #{title}",
        agent_name: to_string(owner),
        metadata: base_metadata(state, %{"task_id" => task_id})
      })

    # Edge from task action node → outcome
    if parent_id = state.task_nodes[task_id] do
      Graph.add_edge(parent_id, node.id, :leads_to)
    end

    {:noreply, state}
  end

  # Task failed
  def handle_info({:task_failed, task_id, owner, reason}, state) do
    title = task_title(task_id)

    {:ok, node} =
      log_node(state, %{
        node_type: :outcome,
        title: "Failed: #{title} — #{truncate(inspect(reason), 120)}",
        agent_name: to_string(owner),
        metadata: base_metadata(state, %{"task_id" => task_id})
      })

    if parent_id = state.task_nodes[task_id] do
      Graph.add_edge(parent_id, node.id, :leads_to)
    end

    {:noreply, state}
  end

  # Keeper created (context offloaded)
  def handle_info({:keeper_created, %{id: keeper_id, topic: topic} = info}, state) do
    log_node(state, %{
      node_type: :observation,
      title: "Context offloaded: #{topic}",
      agent_name: to_string(Map.get(info, :source, "unknown")),
      metadata: base_metadata(state, %{"keeper_id" => keeper_id})
    })

    {:noreply, state}
  end

  # Skip context_offloaded (redundant with keeper_created)
  def handle_info({:context_offloaded, _name, _payload}, state) do
    {:noreply, state}
  end

  # Catch-all for other PubSub messages
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private helpers ---

  defp log_node(state, attrs) do
    attrs =
      attrs
      |> Map.put_new(:metadata, base_metadata(state))
      |> Map.update!(:metadata, &Map.merge(base_metadata(state), &1))

    case Graph.add_node(attrs) do
      {:ok, node} = result ->
        # Try to edge from the active goal (scoped to this team)
        link_to_active_goal(node, state.team_id)
        result

      {:error, reason} = error ->
        Logger.warning("[AutoLogger] Failed to log node: #{inspect(reason)}")
        error
    end
  end

  defp link_to_active_goal(node, team_id) do
    # Only link action and observation nodes to the active goal
    # Outcome nodes get linked to their parent task action instead
    if node.node_type in [:action, :observation] do
      case Graph.list_nodes(node_type: :goal, status: :active, team_id: team_id) do
        [] ->
          :ok

        goals ->
          goal = List.last(goals)
          Graph.add_edge(goal.id, node.id, :leads_to)
      end
    end
  end

  defp base_metadata(state, extra \\ %{}) do
    Map.merge(%{"auto_logged" => true, "team_id" => state.team_id}, extra)
  end

  defp task_title(task_id) do
    case Tasks.get_task(task_id) do
      {:ok, task} -> task.title
      _ -> task_id
    end
  end

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."
end
