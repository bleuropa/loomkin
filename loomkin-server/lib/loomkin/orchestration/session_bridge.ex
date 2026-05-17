defmodule Loomkin.Orchestration.SessionBridge do
  @moduledoc """
  Entry point from `Loomkin.Session.handle_call({:send_message, …})` into the
  orchestration pipelines.

  Routes:

    * `:fast_chat`     → `Loomkin.Orchestration.Pipelines.LitePipeline.run/3`
    * `:tool_use`      → `Loomkin.Orchestration.Pipelines.ShortPipeline.run/3`
    * `:complex_task`  → submitted to `Loomkin.Orchestration.SwarmCoordinator`

  Return values follow the same shape as the legacy session handler so the
  Session GenServer can substitute this call without changing its reply tuple:

      {:ok, response :: String.t()}
      | {:legacy, reason :: String.t()}            # pipeline opted out (skeleton mode)
      | {:complex_task, epic_id :: binary()}       # async pipeline started
      | {:error, term()}
  """

  require Logger

  alias Loomkin.Orchestration.{Context, IntentClassifier, SwarmCoordinator}
  alias Loomkin.Orchestration.Pipelines.{LitePipeline, ShortPipeline}

  @doc """
  Classify + dispatch a single user message.

  `session_state` is the live Session GenServer state (so we can pass team_id,
  workspace_id, current_phase, etc. into the pipelines). `opts` carry per-call
  options like `target_agent`.

  Telemetry: each dispatch emits
  `[:loomkin, :orchestration, :session_bridge, :dispatched]` with
  `%{intent, via}`.
  """
  @spec dispatch(map(), String.t(), keyword()) ::
          {:ok, String.t()}
          | {:legacy, String.t()}
          | {:complex_task, binary()}
          | {:error, term()}
  def dispatch(session_state, message, opts \\ []) when is_map(session_state) do
    case maybe_steering_command(message) do
      {:ok, _} = reply ->
        :telemetry.execute(
          [:loomkin, :orchestration, :session_bridge, :dispatched],
          %{},
          %{intent: :steering, via: :in_band, reason: :orchestration_command}
        )

        reply

      {:error, _} = err ->
        :telemetry.execute(
          [:loomkin, :orchestration, :session_bridge, :dispatched],
          %{},
          %{intent: :steering, via: :in_band, reason: :orchestration_command_error}
        )

        err

      :not_a_command ->
        {intent, via, reason} = IntentClassifier.classify(message, opts)

        :telemetry.execute(
          [:loomkin, :orchestration, :session_bridge, :dispatched],
          %{},
          %{intent: intent, via: via, reason: reason}
        )

        case intent do
          :fast_chat ->
            run_pipeline(LitePipeline, session_state, message, opts)

          :tool_use ->
            run_pipeline(ShortPipeline, session_state, message, opts)

          :complex_task ->
            submit_complex_task(session_state, message, opts)
        end
    end
  end

  ## ─── In-band steering commands ─────────────────────────────────────────

  # Recognise `/orchestration <verb> <epic_id>` and route to SwarmCoordinator.
  # Returns `{:ok, "<verb>d epic <id>"}` on success so the Session emits a
  # confirmation assistant message; `{:error, reason}` on bad syntax/lookup;
  # or `:not_a_command` when the message isn't a steering command.
  defp maybe_steering_command(text) when is_binary(text) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, "/orchestration ") do
      parse_and_route(trimmed)
    else
      :not_a_command
    end
  end

  defp maybe_steering_command(_), do: :not_a_command

  defp parse_and_route(text) do
    case String.split(text, ~r/\s+/, trim: true) do
      ["/orchestration", verb, epic_id] when is_binary(verb) and is_binary(epic_id) ->
        run_steering(verb, epic_id)

      _ ->
        {:error, "usage: /orchestration <pause|cancel|resume|approve|reject> <epic_id>"}
    end
  end

  defp run_steering(verb, epic_id) do
    case verb do
      "pause" -> dispatch_verb(:pause, epic_id, "paused")
      "cancel" -> dispatch_verb(:cancel, epic_id, "cancelled")
      "resume" -> dispatch_verb(:resume, epic_id, "resumed")
      "approve" -> dispatch_verb(:approve, epic_id, "approved")
      "reject" -> dispatch_verb(:reject, epic_id, "rejected")
      other -> {:error, "unknown orchestration command: #{other}"}
    end
  end

  defp dispatch_verb(verb, epic_id, past_tense) do
    case apply(SwarmCoordinator, verb, [epic_id]) do
      :ok -> {:ok, "#{past_tense} epic #{epic_id}"}
      {:ok, _} -> {:ok, "#{past_tense} epic #{epic_id}"}
      {:error, reason} -> {:error, "could not #{verb} epic #{epic_id}: #{inspect(reason)}"}
      other -> {:error, "unexpected response from coordinator: #{inspect(other)}"}
    end
  end

  # Pipelines may return :ok / :legacy / :error. Translate :error into a
  # :legacy fallback so the Session GenServer's case-arm needs only the three
  # outcomes it actually knows how to handle. The underlying reason is logged
  # for observability.
  defp run_pipeline(pipeline_mod, session_state, message, opts) do
    case pipeline_mod.run(session_state, message, opts) do
      {:ok, response} when is_binary(response) ->
        {:ok, response}

      {:legacy, _reason} = legacy ->
        legacy

      {:error, reason} ->
        Logger.info(
          "[session_bridge] #{inspect(pipeline_mod)} returned error #{inspect(reason)}; falling back to :legacy"
        )

        {:legacy, "pipeline #{inspect(pipeline_mod)} returned error: #{inspect(reason)}"}

      other ->
        Logger.warning(
          "[session_bridge] #{inspect(pipeline_mod)} returned unexpected value #{inspect(other)}; falling back to :legacy"
        )

        {:legacy, "pipeline #{inspect(pipeline_mod)} returned unexpected: #{inspect(other)}"}
    end
  end

  defp submit_complex_task(session_state, message, opts) do
    epic_attrs = %{
      title: title_from(message),
      spec: message,
      created_by: Map.get(session_state, :id),
      metadata: %{
        session_id: Map.get(session_state, :id),
        team_id: Map.get(session_state, :team_id),
        workspace_id: Map.get(session_state, :workspace_id)
      }
    }

    callbacks = Keyword.get(opts, :callbacks, default_callbacks())

    # Persist the Epic row first so we have a stable id to share with the
    # in-memory orchestrator. The orchestrator's `persist_phase/2` later
    # updates this same row by id.
    case Context.create_epic(epic_attrs) do
      {:ok, epic} ->
        submit_attrs = epic_attrs |> Map.put(:id, epic.id)

        case SwarmCoordinator.submit(submit_attrs, callbacks: callbacks) do
          {:ok, _pid} ->
            {:complex_task, epic.id}

          {:error, reason} ->
            Logger.warning(
              "complex_task epic #{epic.id} persisted but SwarmCoordinator.submit/2 failed: #{inspect(reason)}; returning :legacy fallback"
            )

            {:legacy,
             "complex_task persisted as epic #{epic.id} but orchestrator failed to spawn: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, {:complex_task_persist_failed, reason}}
    end
  end

  defp default_callbacks do
    Loomkin.Orchestration.Callbacks.default_issue_callbacks()
  end

  defp title_from(message) do
    message
    |> String.split("\n", parts: 2)
    |> List.first()
    |> Kernel.||("untitled")
    |> String.slice(0, 80)
  end
end
