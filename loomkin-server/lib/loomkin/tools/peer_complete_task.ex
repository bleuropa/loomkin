defmodule Loomkin.Tools.PeerCompleteTask do
  @moduledoc "Agent-initiated task completion with artifact verification."

  require Logger

  use Jido.Action,
    name: "peer_complete_task",
    description:
      "Mark a task as completed with a result summary and optional structured details. " <>
        "Broadcasts task_completed so the team knows the task is done. " <>
        "You MUST provide a meaningful result AND at least one of: actions_taken, " <>
        "discoveries, or files_changed. Empty completions will be rejected.",
    schema: [
      team_id: [type: :string, required: true, doc: "Team ID"],
      task_id: [type: :string, required: true, doc: "ID of the task to complete"],
      result: [type: :string, doc: "Result summary or output of the completed task"],
      actions_taken: [type: {:list, :string}, doc: "Concrete actions taken during the task"],
      discoveries: [type: {:list, :string}, doc: "Things learned during the task"],
      files_changed: [type: {:list, :string}, doc: "File paths created or modified"],
      decisions_made: [type: {:list, :string}, doc: "Choices made and brief rationale"],
      open_questions: [type: {:list, :string}, doc: "Unresolved issues for successor tasks"]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  alias Loomkin.Teams.ContextOffload
  alias Loomkin.Teams.Tasks

  @impl true
  def run(params, context) do
    team_id = param!(params, :team_id)
    task_id = param!(params, :task_id)
    project_path = param(context, :project_path)

    completion_attrs = %{
      result: param(params, :result) || "",
      actions_taken: param(params, :actions_taken) || [],
      discoveries: param(params, :discoveries) || [],
      files_changed: param(params, :files_changed) || [],
      decisions_made: param(params, :decisions_made) || [],
      open_questions: param(params, :open_questions) || []
    }

    # Validate that the agent actually produced something
    case validate_completion_quality(completion_attrs) do
      :ok ->
        # Verify claimed files actually exist on disk
        file_warnings = verify_files_changed(completion_attrs.files_changed, project_path)
        do_complete(team_id, task_id, completion_attrs, file_warnings, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_completion_quality(attrs) do
    result = attrs.result
    actions = attrs.actions_taken
    discoveries = attrs.discoveries
    files = attrs.files_changed

    has_result = is_binary(result) and String.length(String.trim(result)) > 20
    has_actions = is_list(actions) and actions != []
    has_discoveries = is_list(discoveries) and discoveries != []
    has_files = is_list(files) and files != []

    cond do
      not has_result ->
        {:error,
         "Task completion rejected: you must provide a meaningful result summary (>20 chars). " <>
           "Describe what you actually accomplished, with specific details."}

      not (has_actions or has_discoveries or has_files) ->
        {:error,
         "Task completion rejected: you must provide at least one of actions_taken, " <>
           "discoveries, or files_changed. If you haven't produced any artifacts, " <>
           "you haven't completed the task — keep working."}

      true ->
        :ok
    end
  end

  @doc false
  def verify_files_changed([], _project_path), do: []
  def verify_files_changed(_files, nil), do: []

  def verify_files_changed(files, project_path) when is_list(files) do
    files
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.flat_map(fn file_path ->
      full_path = Path.expand(file_path, project_path)

      if File.exists?(full_path) do
        []
      else
        Logger.warning(
          "[PeerCompleteTask] Claimed file does not exist: #{file_path} (resolved: #{full_path})"
        )

        ["#{file_path} (not found on disk)"]
      end
    end)
  end

  defp do_complete(team_id, task_id, completion_attrs, file_warnings, context) do
    case Tasks.get_task(task_id) do
      {:error, :not_found} ->
        {:error, "Task not found: #{task_id}"}

      {:ok, task} when task.team_id != team_id ->
        # Allow cross-team task completion when a parent team creates tasks
        # for child team agents. Log it but don't block.
        Logger.info(
          "[PeerCompleteTask] Cross-team completion: agent team=#{team_id}, task team=#{task.team_id}, task=#{task_id}"
        )

        do_complete_task(task, completion_attrs, file_warnings, context)

      {:ok, task} ->
        do_complete_task(task, completion_attrs, file_warnings, context)
    end
  end

  defp do_complete_task(task, completion_attrs, file_warnings, context) do
    case maybe_persist_research_findings(task, completion_attrs, context) do
      {:error, reason} ->
        {:error, reason}

      {:ok, publication_note} ->
        case Tasks.complete_task(task.id, completion_attrs) do
          {:ok, task} ->
            artifact_count =
              length(completion_attrs.actions_taken) +
                length(completion_attrs.discoveries) +
                length(completion_attrs.files_changed)

            warning_section =
              if file_warnings != [] do
                "\n  ⚠ File verification warnings: #{Enum.join(file_warnings, ", ")}"
              else
                ""
              end

            publication_section =
              case publication_note do
                "" -> ""
                note -> "\n  Findings published: #{note}"
              end

            verified_count = length(completion_attrs.files_changed) - length(file_warnings)

            summary = """
            Task completed:
              ID: #{task.id}
              Title: #{task.title}
              Status: #{task.status}
              Artifacts: #{artifact_count} (#{length(completion_attrs.actions_taken)} actions, #{length(completion_attrs.discoveries)} discoveries, #{length(completion_attrs.files_changed)} files)
              Files verified: #{verified_count}/#{length(completion_attrs.files_changed)}#{warning_section}#{publication_section}
            """

            {:ok, %{result: String.trim(summary), task_id: task.id}}

          {:error, reason} ->
            {:error, "Failed to complete task: #{inspect(reason)}"}
        end
    end
  end

  defp maybe_persist_research_findings(task, completion_attrs, context) do
    if researcher_role?(context) do
      publication_state = param(context, :publication_state) || %{}

      if publication_state[:offloaded] do
        {:ok, ""}
      else
        auto_publish_research_findings(task, completion_attrs, context)
      end
    else
      {:ok, ""}
    end
  end

  defp auto_publish_research_findings(task, completion_attrs, context) do
    team_id = task.team_id
    agent_name = param(context, :agent_name) || task.owner || "researcher"
    topic = build_research_topic(task)

    metadata = %{
      "source" => "peer_complete_task",
      "task_id" => task.id,
      "task_title" => task.title,
      "kind" => "research_findings"
    }

    case ContextOffload.offload_to_keeper(
           team_id,
           agent_name,
           build_research_offload_messages(task, completion_attrs, agent_name),
           topic: topic,
           metadata: metadata
         ) do
      {:ok, _pid, index_entry} ->
        publish_findings_offloaded(agent_name, team_id, %{
          topic: topic,
          source: "peer_complete_task",
          task_id: task.id,
          index_entry: index_entry
        })

        {:ok, "#{topic} (auto-offloaded from task completion)"}

      {:error, reason} ->
        {:error,
         "Task completion rejected: failed to persist research findings before completion. " <>
           "Try again after context_offload succeeds. Reason: #{inspect(reason)}"}
    end
  end

  defp build_research_topic(task) do
    title =
      task.title
      |> to_string()
      |> String.trim()

    "research: #{title}"
    |> String.slice(0, 80)
  end

  defp build_research_offload_messages(task, attrs, agent_name) do
    body = """
    Task: #{task.title}
    Researcher: #{agent_name}
    Completed at: #{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}

    Result
    #{attrs.result}

    Discoveries
    #{format_bullet_list(attrs.discoveries)}

    Actions Taken
    #{format_bullet_list(attrs.actions_taken)}

    Decisions Made
    #{format_bullet_list(attrs.decisions_made)}

    Open Questions
    #{format_bullet_list(attrs.open_questions)}

    Files Changed
    #{format_bullet_list(attrs.files_changed)}
    """

    [
      %{
        role: :system,
        content: "Research findings persisted from peer_complete_task for later retrieval."
      },
      %{role: :assistant, content: String.trim(body)}
    ]
  end

  defp format_bullet_list([]), do: "- none"

  defp format_bullet_list(items) do
    items
    |> Enum.map(&"- #{&1}")
    |> Enum.join("\n")
  end

  defp researcher_role?(context) do
    case param(context, :role) do
      :researcher -> true
      "researcher" -> true
      _ -> false
    end
  end

  defp publish_findings_offloaded(agent_name, team_id, payload) do
    signal =
      Loomkin.Signals.Context.Offloaded.new!(
        %{agent_name: to_string(agent_name), team_id: team_id},
        subject: "payload"
      )
      |> Map.put(
        :data,
        Map.put(%{agent_name: to_string(agent_name), team_id: team_id}, :payload, payload)
      )

    Loomkin.Signals.publish(signal)
  end
end
