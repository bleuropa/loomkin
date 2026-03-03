defmodule Loomkin.Channels.Severity do
  @moduledoc """
  Classifies PubSub events into severity levels for channel notification filtering.

  Severity levels:
  - `:urgent` — requires immediate attention (ask_user, errors, team dissolved, permission requests)
  - `:action` — actionable updates (agent messages, task completions, conflicts, consensus)
  - `:info` — informational (context updates, other collab events, status changes)
  - `:noise` — always suppressed (stream deltas, tool executing, usage telemetry)
  """

  @type severity :: :urgent | :action | :info | :noise

  @doc "Classify a PubSub event tuple into a severity level."
  @spec classify(term()) :: severity()
  def classify({:ask_user_question, _}), do: :urgent
  def classify({:agent_error, _}), do: :urgent
  def classify(:team_dissolved), do: :urgent
  def classify({:permission_request, _, _, _, _}), do: :urgent

  def classify({:new_message, _}), do: :action
  def classify({:collab_event, %{type: :conflict_detected}}), do: :action
  def classify({:collab_event, %{type: :consensus_reached}}), do: :action
  def classify({:collab_event, %{type: :task_completed}}), do: :action

  def classify({:collab_event, _}), do: :info
  def classify({:context_update, _}), do: :info
  def classify({:channel_message, _}), do: :info

  # Session events
  def classify({:session_cancelled, _}), do: :urgent
  def classify({:llm_error, _, _}), do: :urgent
  def classify({:session_status, _, _}), do: :info
  def classify({:team_available, _, _}), do: :info
  def classify({:child_team_available, _, _}), do: :info
  def classify({:new_message, _, _}), do: :action
  def classify({:stream_start, _}), do: :noise
  def classify({:stream_end, _}), do: :noise

  # Telemetry events
  def classify({:team_budget_warning, _}), do: :urgent
  def classify({:team_escalation, _}), do: :action
  def classify({:team_llm_stop, _}), do: :info

  def classify({:stream_delta, _}), do: :noise
  def classify({:stream_delta, _, _}), do: :noise
  def classify({:tool_executing, _}), do: :noise
  def classify({:usage, _}), do: :noise

  def classify(_), do: :info

  @doc "Check if a severity level is included in the notify config."
  @spec notify?(severity(), [String.t()] | [atom()]) :: boolean()
  def notify?(:noise, _levels), do: false

  def notify?(severity, levels) do
    severity_str = to_string(severity)
    Enum.any?(levels, fn level -> to_string(level) == severity_str end)
  end

  @doc "Default severity levels to forward."
  @spec default_levels() :: [String.t()]
  def default_levels, do: ["urgent", "action"]
end
