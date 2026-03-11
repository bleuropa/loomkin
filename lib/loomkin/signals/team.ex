defmodule Loomkin.Signals.Team do
  @moduledoc "Team-domain signals: dissolution, permissions, ask-user, child teams."

  defmodule Dissolved do
    use Jido.Signal,
      type: "team.dissolved",
      schema: [
        team_id: [type: :string, required: true]
      ]
  end

  defmodule PermissionRequest do
    use Jido.Signal,
      type: "team.permission.request",
      schema: [
        team_id: [type: :string, required: true],
        tool_name: [type: :string, required: true],
        tool_path: [type: :string, required: false]
      ]
  end

  defmodule AskUserQuestion do
    use Jido.Signal,
      type: "team.ask_user.question",
      schema: [
        question_id: [type: :string, required: true],
        agent_name: [type: :string, required: true],
        team_id: [type: :string, required: true],
        question: [type: :string, required: true]
      ]
  end

  defmodule AskUserAnswered do
    use Jido.Signal,
      type: "team.ask_user.answered",
      schema: [
        question_id: [type: :string, required: true],
        answer: [type: :string, required: true]
      ]
  end

  defmodule ChildTeamCreated do
    use Jido.Signal,
      type: "team.child.created",
      schema: [
        team_id: [type: :string, required: true],
        parent_team_id: [type: :string, required: false],
        team_name: [type: :string, required: true],
        depth: [type: :integer, required: true]
      ]
  end

  defmodule TaskAssigned do
    use Jido.Signal,
      type: "team.task.assigned",
      schema: [
        task_id: [type: :string, required: true],
        agent_name: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskCompleted do
    use Jido.Signal,
      type: "team.task.completed",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskFailed do
    use Jido.Signal,
      type: "team.task.failed",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskStarted do
    use Jido.Signal,
      type: "team.task.started",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule RebalanceNeeded do
    use Jido.Signal,
      type: "team.rebalance.needed",
      schema: [
        agent_name: [type: :string, required: true],
        task_info: [type: :string, required: false],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule ConflictDetected do
    use Jido.Signal,
      type: "team.conflict.detected",
      schema: [
        team_id: [type: :string, required: true]
      ]
  end

  defmodule BudgetWarning do
    use Jido.Signal,
      type: "team.budget.warning",
      schema: [
        team_id: [type: :string, required: true]
      ]
  end

  defmodule LlmStop do
    use Jido.Signal,
      type: "team.llm.stop",
      schema: [
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskMilestoneReached do
    use Jido.Signal,
      type: "team.task.milestone",
      schema: [
        task_id: [type: :string, required: true],
        milestone_name: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskPriorityChanged do
    use Jido.Signal,
      type: "team.task.priority_changed",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        new_priority: [type: :integer, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskReadyForReview do
    use Jido.Signal,
      type: "team.task.ready_for_review",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskBlocked do
    use Jido.Signal,
      type: "team.task.blocked",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule TaskPartiallyComplete do
    use Jido.Signal,
      type: "team.task.partially_complete",
      schema: [
        task_id: [type: :string, required: true],
        owner: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule RendezvousCreated do
    use Jido.Signal,
      type: "team.rendezvous.created",
      schema: [
        rendezvous_id: [type: :string, required: true],
        name: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule RendezvousCompleted do
    use Jido.Signal,
      type: "team.rendezvous.completed",
      schema: [
        rendezvous_id: [type: :string, required: true],
        name: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end

  defmodule RendezvousTimedOut do
    use Jido.Signal,
      type: "team.rendezvous.timed_out",
      schema: [
        rendezvous_id: [type: :string, required: true],
        name: [type: :string, required: true],
        team_id: [type: :string, required: true]
      ]
  end
end
