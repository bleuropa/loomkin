defmodule Loomkin.Teams.Tasks do
  @moduledoc "CRUD + coordination logic for team tasks."

  import Ecto.Query
  alias Loomkin.Repo
  alias Loomkin.Schemas.TeamTask
  alias Loomkin.Schemas.TeamTaskDep
  alias Loomkin.Teams.Capabilities
  alias Loomkin.Teams.Comms
  alias Loomkin.Teams.Context
  alias Loomkin.Teams.CostTracker
  alias Loomkin.Teams.Learning

  def create_task(team_id, attrs) do
    %TeamTask{}
    |> TeamTask.changeset(Map.merge(attrs, %{team_id: team_id, status: :pending}))
    |> Repo.insert()
    |> tap_ok(fn task ->
      Comms.broadcast_task_event(team_id, {:task_created, task.id, task.title})

      Context.cache_task(team_id, task.id, %{
        title: task.title,
        status: task.status,
        owner: task.owner
      })
    end)
  end

  def assign_task(task_id, agent_name) do
    get_task!(task_id)
    |> TeamTask.changeset(%{owner: agent_name, status: :assigned})
    |> Repo.update()
    |> tap_ok(fn task ->
      Comms.broadcast_task_event(task.team_id, {:task_assigned, task.id, agent_name})

      Context.cache_task(task.team_id, task.id, %{
        title: task.title,
        status: :assigned,
        owner: agent_name
      })
    end)
  end

  def start_task(task_id) do
    get_task!(task_id)
    |> TeamTask.changeset(%{status: :in_progress})
    |> Repo.update()
    |> tap_ok(fn task ->
      Comms.broadcast_task_event(task.team_id, {:task_started, task.id, task.owner})

      Context.cache_task(task.team_id, task.id, %{
        title: task.title,
        status: :in_progress,
        owner: task.owner
      })
    end)
  end

  def complete_task(task_id, result) do
    task = get_task!(task_id)

    if task.status in [:completed, :failed] do
      {:ok, task}
    else
      task
      |> TeamTask.changeset(%{status: :completed, result: result})
      |> Repo.update()
      |> tap_ok(fn task ->
        # Persist accumulated cost/tokens from CostTracker for the owning agent
        if task.owner do
          usage = CostTracker.get_agent_usage(task.team_id, task.owner)

          CostTracker.persist_task_cost(
            task.id,
            usage.cost,
            usage.input_tokens + usage.output_tokens
          )
        end

        Comms.broadcast_task_event(task.team_id, {:task_completed, task.id, task.owner, result})

        Context.cache_task(task.team_id, task.id, %{
          title: task.title,
          status: :completed,
          owner: task.owner
        })

        record_capability(task, :success)
        record_learning_metric(task, true)
        auto_schedule_unblocked(task.team_id)
      end)
    end
  end

  def fail_task(task_id, reason) do
    case Ecto.UUID.cast(task_id) do
      :error ->
        {:error, :not_a_db_task}

      {:ok, _} ->
        task = get_task!(task_id)

        if task.status in [:completed, :failed] do
          {:ok, task}
        else
          task
          |> TeamTask.changeset(%{status: :failed, result: reason})
          |> Repo.update()
          |> tap_ok(fn task ->
            Comms.broadcast_task_event(task.team_id, {:task_failed, task.id, task.owner, reason})

            Context.cache_task(task.team_id, task.id, %{
              title: task.title,
              status: :failed,
              owner: task.owner
            })

            record_capability(task, :failure)
            record_learning_metric(task, false)
          end)
        end
    end
  end

  def mark_ready_for_review(task_id, summary) do
    task = get_task!(task_id)

    if task.status != :in_progress do
      {:error, :invalid_transition}
    else
      task
      |> TeamTask.changeset(%{status: :ready_for_review, result: summary})
      |> Repo.update()
      |> tap_ok(fn task ->
        Comms.broadcast_task_event(
          task.team_id,
          {:task_ready_for_review, task.id, task.owner, summary}
        )

        Context.cache_task(task.team_id, task.id, %{
          title: task.title,
          status: :ready_for_review,
          owner: task.owner
        })
      end)
    end
  end

  def mark_blocked(task_id, reason) do
    task = get_task!(task_id)

    if task.status not in [:assigned, :in_progress] do
      {:error, :invalid_transition}
    else
      task
      |> TeamTask.changeset(%{status: :blocked, result: reason})
      |> Repo.update()
      |> tap_ok(fn task ->
        Comms.broadcast_task_event(task.team_id, {:task_blocked, task.id, task.owner, reason})

        Context.cache_task(task.team_id, task.id, %{
          title: task.title,
          status: :blocked,
          owner: task.owner
        })
      end)
    end
  end

  def mark_partially_complete(task_id, partial_result) do
    task = get_task!(task_id)

    if task.status != :in_progress do
      {:error, :invalid_transition}
    else
      task
      |> TeamTask.changeset(%{status: :partially_complete, result: partial_result})
      |> Repo.update()
      |> tap_ok(fn task ->
        Comms.broadcast_task_event(
          task.team_id,
          {:task_partially_complete, task.id, task.owner, partial_result}
        )

        Context.cache_task(task.team_id, task.id, %{
          title: task.title,
          status: :partially_complete,
          owner: task.owner
        })
      end)
    end
  end

  @doc """
  Add a dependency between two tasks.

  ## Options

    * `:milestone_name` - optional milestone name for milestone-based deps

  Returns `{:ok, dep}` or `{:error, reason}`.
  Rejects cycles (up to 10 levels deep).
  """
  def add_dependency(task_id, depends_on_id, dep_type \\ :blocks, opts \\ []) do
    milestone_name = Keyword.get(opts, :milestone_name)

    if detect_cycle?(depends_on_id, task_id) do
      {:error, :cycle_detected}
    else
      %TeamTaskDep{}
      |> TeamTaskDep.changeset(%{
        task_id: task_id,
        depends_on_id: depends_on_id,
        dep_type: dep_type,
        milestone_name: milestone_name
      })
      |> Repo.insert()
    end
  end

  @doc """
  Returns predecessor output data for all completed `:requires_output` dependencies.

  Returns `[%{task_id: id, title: title, result: result}]`.
  """
  def get_predecessor_outputs(task_id) do
    Repo.all(
      from d in TeamTaskDep,
        join: dep in TeamTask,
        on: d.depends_on_id == dep.id,
        where:
          d.task_id == ^task_id and d.dep_type == :requires_output and dep.status == :completed,
        select: %{task_id: dep.id, title: dep.title, result: dep.result}
    )
  end

  @doc """
  Emit a named milestone for a task.

  Appends the milestone to `milestones_emitted`, broadcasts a signal,
  and checks if any milestone-dependent tasks are now unblocked.
  """
  def emit_milestone(team_id, task_id, milestone_name) do
    task = get_task!(task_id)

    if milestone_name in (task.milestones_emitted || []) do
      {:ok, task}
    else
      new_milestones = (task.milestones_emitted || []) ++ [milestone_name]

      task
      |> TeamTask.changeset(%{milestones_emitted: new_milestones})
      |> Repo.update()
      |> tap_ok(fn updated_task ->
        Comms.broadcast_task_event(
          team_id,
          {:task_milestone, updated_task.id, updated_task.owner, milestone_name}
        )

        check_milestone_unblocks(team_id, milestone_name)
      end)
    end
  end

  @doc """
  Check if any tasks depending on the given milestone are now fully unblocked.

  Queries deps with matching `milestone_name`, then verifies if the dependent
  tasks have all their blocking deps satisfied.
  """
  def check_milestone_unblocks(team_id, milestone_name) do
    # Find task_ids that depend on this milestone
    dependent_task_ids =
      Repo.all(
        from d in TeamTaskDep,
          join: t in TeamTask,
          on: d.task_id == t.id,
          where: t.team_id == ^team_id and d.milestone_name == ^milestone_name,
          select: d.task_id,
          distinct: true
      )

    if dependent_task_ids != [] do
      blocked_ids = blocked_task_ids(team_id)

      newly_unblocked =
        dependent_task_ids
        |> Enum.reject(fn id -> id in blocked_ids end)

      if newly_unblocked != [] do
        Comms.broadcast_task_event(team_id, {:tasks_unblocked, newly_unblocked})
      end
    end
  end

  @doc """
  Detect if adding an edge from `from_id` to `to_id` would create a cycle.

  Performs a DFS from `to_id` looking for `from_id`, limited to 10 levels deep.
  Returns `true` if a cycle would be created.
  """
  def detect_cycle?(from_id, to_id, max_depth \\ 10) do
    visited = MapSet.new()
    do_detect_cycle(to_id, from_id, visited, 0, max_depth)
  end

  @doc """
  Propagate priority to blocking predecessors.

  When a task's priority is raised, recursively propagate to predecessors
  that have a lower (numerically higher) priority value.
  """
  def propagate_priority(task_id, new_priority) do
    predecessors =
      Repo.all(
        from d in TeamTaskDep,
          join: dep in TeamTask,
          on: d.depends_on_id == dep.id,
          where: d.task_id == ^task_id and d.dep_type in [:blocks, :requires_output],
          select: dep
      )

    Enum.each(predecessors, fn pred ->
      if pred.priority > new_priority do
        pred
        |> TeamTask.changeset(%{priority: new_priority})
        |> Repo.update()
        |> tap_ok(fn updated ->
          Comms.broadcast_task_event(
            updated.team_id,
            {:task_priority_changed, updated.id, updated.owner, new_priority}
          )

          propagate_priority(updated.id, new_priority)
        end)
      end
    end)
  end

  def list_available(team_id) do
    pending_tasks =
      Repo.all(
        from t in TeamTask,
          where: t.team_id == ^team_id and t.status == :pending,
          order_by: [asc: t.priority, asc: t.inserted_at]
      )

    blocked_ids = blocked_task_ids(team_id)

    Enum.reject(pending_tasks, fn t -> t.id in blocked_ids end)
  end

  def list_by_agent(team_id, agent_name) do
    Repo.all(
      from t in TeamTask,
        where: t.team_id == ^team_id and t.owner == ^agent_name,
        order_by: [asc: t.priority, asc: t.inserted_at]
    )
  end

  def list_all(team_id) do
    Repo.all(
      from t in TeamTask,
        where: t.team_id == ^team_id,
        order_by: [asc: t.priority, asc: t.inserted_at]
    )
  end

  @doc "Returns {tasks, deps} tuple with all tasks and their dependency records for a team."
  def list_with_deps(team_id) do
    tasks = list_all(team_id)
    task_ids = Enum.map(tasks, & &1.id)

    deps =
      if task_ids == [] do
        []
      else
        Repo.all(
          from d in TeamTaskDep,
            where: d.task_id in ^task_ids or d.depends_on_id in ^task_ids
        )
      end

    {tasks, deps}
  end

  @doc "List tasks from sibling teams for cross-team visibility."
  def list_cross_team_tasks(team_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    case Loomkin.Teams.Manager.get_sibling_teams(team_id) do
      {:ok, siblings} ->
        siblings
        |> Enum.flat_map(fn sib_id -> list_all(sib_id) end)
        |> Enum.take(limit)

      :error ->
        []
    end
  end

  def get_task(task_id) do
    case Ecto.UUID.cast(task_id) do
      :error ->
        {:error, :not_found}

      {:ok, _} ->
        case Repo.get(TeamTask, task_id) do
          nil -> {:error, :not_found}
          task -> {:ok, task}
        end
    end
  end

  @doc """
  Smart-assign a task to the best available agent based on capabilities and load.

  Returns `{:ok, task, reasoning}` or `{:error, reason}`.
  """
  def smart_assign(team_id, task_id) do
    with {:ok, task} <- get_task(task_id),
         {:ok, agent_name, reason} <- pick_best_agent(team_id, task) do
      case assign_task(task_id, agent_name) do
        {:ok, task} ->
          Comms.broadcast(team_id, {:smart_assigned, task.id, agent_name, reason})
          {:ok, task, reason}

        error ->
          error
      end
    end
  end

  defp pick_best_agent(team_id, task) do
    agents = Context.list_agents(team_id)
    idle_agents = Enum.filter(agents, fn a -> a.status == :idle end)

    if idle_agents == [] do
      {:error, :no_idle_agents}
    else
      task_type = Capabilities.infer_task_type(task.title)
      ranked = Capabilities.best_agent_for(team_id, task_type)
      idle_names = MapSet.new(idle_agents, & &1.name)

      # Find best ranked agent that is idle
      best_capable =
        Enum.find(ranked, fn entry -> MapSet.member?(idle_names, entry.agent) end)

      case best_capable do
        %{agent: name, score: score} when score > 0 ->
          {:ok, name, "Best at #{task_type} (score: #{Float.round(score, 2)})"}

        _ ->
          # Fall back to least-loaded idle agent
          agent_loads = agent_load_counts(team_id)

          least_loaded =
            idle_agents
            |> Enum.min_by(fn a -> Map.get(agent_loads, a.name, 0) end)

          load = Map.get(agent_loads, least_loaded.name, 0)
          {:ok, least_loaded.name, "Least loaded idle agent (#{load} active tasks)"}
      end
    end
  end

  defp agent_load_counts(team_id) do
    Repo.all(
      from t in TeamTask,
        where: t.team_id == ^team_id and t.status in [:assigned, :in_progress],
        group_by: t.owner,
        select: {t.owner, count(t.id)}
    )
    |> Enum.into(%{})
  end

  # -- Private --

  defp get_task!(task_id) do
    case Ecto.UUID.cast(task_id) do
      {:ok, _} -> Repo.get!(TeamTask, task_id)
      :error -> raise Ecto.NoResultsError, queryable: TeamTask
    end
  end

  defp blocked_task_ids(team_id) do
    blocking_types = [:blocks, :requires_output]

    # Tasks blocked by incomplete :blocks or :requires_output deps
    task_blocked =
      Repo.all(
        from d in TeamTaskDep,
          join: t in TeamTask,
          on: d.task_id == t.id,
          join: dep in TeamTask,
          on: d.depends_on_id == dep.id,
          where:
            t.team_id == ^team_id and d.dep_type in ^blocking_types and
              dep.status != :completed and is_nil(d.milestone_name),
          select: d.task_id,
          distinct: true
      )

    # Tasks blocked by milestone deps where the milestone hasn't been emitted yet
    milestone_blocked =
      Repo.all(
        from d in TeamTaskDep,
          join: t in TeamTask,
          on: d.task_id == t.id,
          join: dep in TeamTask,
          on: d.depends_on_id == dep.id,
          where:
            t.team_id == ^team_id and not is_nil(d.milestone_name) and
              fragment("? != ALL(?)", d.milestone_name, dep.milestones_emitted),
          select: d.task_id,
          distinct: true
      )

    Enum.uniq(task_blocked ++ milestone_blocked)
  end

  defp auto_schedule_unblocked(team_id) do
    available = list_available(team_id)

    if available != [] do
      task_ids = Enum.map(available, & &1.id)

      # Gather predecessor outputs for tasks with :requires_output deps
      predecessor_outputs =
        task_ids
        |> Enum.map(fn id -> {id, get_predecessor_outputs(id)} end)
        |> Enum.reject(fn {_id, outputs} -> outputs == [] end)
        |> Enum.into(%{})

      Comms.broadcast_task_event(
        team_id,
        {:tasks_unblocked, task_ids, predecessor_outputs}
      )
    end
  end

  defp record_learning_metric(task, success?) do
    if task.owner do
      usage = CostTracker.get_agent_usage(task.team_id, task.owner)

      Learning.record_task_result(%{
        team_id: task.team_id,
        agent_name: task.owner,
        role: task.role || "unknown",
        model: usage[:model] || "unknown",
        task_type: task.task_type || task.title || "general",
        success: success?,
        cost_usd: usage.cost,
        tokens_used: (usage[:input_tokens] || 0) + (usage[:output_tokens] || 0)
      })
    end
  rescue
    _ -> :ok
  end

  defp record_capability(task, outcome) do
    if task.owner do
      task_type = Capabilities.infer_task_type(task.title)
      Capabilities.record_completion(task.team_id, task.owner, task_type, outcome)
    end
  rescue
    _ -> :ok
  end

  defp do_detect_cycle(_current, _target, _visited, depth, max_depth) when depth >= max_depth do
    false
  end

  defp do_detect_cycle(current, target, _visited, _depth, _max_depth) when current == target do
    true
  end

  defp do_detect_cycle(current, target, visited, depth, max_depth) do
    if MapSet.member?(visited, current) do
      false
    else
      visited = MapSet.put(visited, current)

      deps =
        Repo.all(
          from d in TeamTaskDep,
            where: d.task_id == ^current,
            select: d.depends_on_id
        )

      Enum.any?(deps, fn dep_id ->
        do_detect_cycle(dep_id, target, visited, depth + 1, max_depth)
      end)
    end
  end

  defp tap_ok({:ok, val} = result, fun) do
    fun.(val)
    result
  end

  defp tap_ok(error, _fun), do: error
end
