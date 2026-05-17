defmodule Loomkin.Orchestration.Approval do
  @moduledoc """
  Mid-flight approval intercept for `Loomkin.Orchestration.IssueOrchestrator`.

  At each gate-verdict transition (and before each commit boundary) the
  orchestrator consults `maybe_block/2`. The user's
  `orchestration_approval_mode` is read from `epic.metadata["user_id"]` (or
  `:user_id`) and decides whether the run continues or pauses in
  `:awaiting_approval`.

  Modes:

    * `"auto"`         — never blocks (default; preserves today's behaviour).
    * `"commit"`       — blocks once, immediately before the `:pr` phase.
                          `:pr` is the safe checkpoint just before we open a
                          PR for the work the executor committed.
    * `"every_phase"`  — blocks at every gate transition AND before `:pr`.

  Returns:

      :continue
    | {:block, reason :: String.t()}

  Missing user_id, missing user row, unknown mode → `:continue`. This keeps
  test fixtures (which never set `user_id`) working unchanged.
  """

  @type mode :: :auto | :commit | :every_phase
  @type verdict :: :continue | {:block, String.t()}

  # Phases that count as "a gate boundary just resolved". Used by :every_phase.
  @gate_phases ~w(plan_review design_review final_review)a

  @doc """
  Decides whether the orchestrator should pause for approval before
  transitioning away from `phase`.

  `epic` is the in-memory map carried by the orchestrator (it may be a real
  `%Schema.Epic{}` or a bare map from a test fixture).
  """
  @spec maybe_block(map(), atom()) :: verdict()
  def maybe_block(epic, phase) when is_map(epic) and is_atom(phase) do
    case approval_mode_for(epic) do
      :auto -> :continue
      :commit -> block_if_pr(phase)
      :every_phase -> block_if_gate_or_pr(phase)
      _ -> :continue
    end
  end

  def maybe_block(_, _), do: :continue

  ## Helpers

  defp block_if_pr(:pr), do: {:block, "approval required before opening PR"}
  defp block_if_pr(_), do: :continue

  defp block_if_gate_or_pr(:pr), do: {:block, "approval required before opening PR"}

  defp block_if_gate_or_pr(phase) do
    if phase in @gate_phases do
      {:block, "approval required after #{phase}"}
    else
      :continue
    end
  end

  defp approval_mode_for(epic) do
    with user_id when is_binary(user_id) <- user_id_from(epic),
         %{orchestration_approval_mode: mode} when is_binary(mode) <- load_user(user_id) do
      parse_mode(mode)
    else
      _ -> :auto
    end
  end

  defp user_id_from(epic) do
    metadata = Map.get(epic, :metadata) || Map.get(epic, "metadata") || %{}

    case Map.get(metadata, "user_id") || Map.get(metadata, :user_id) do
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  defp load_user(user_id) do
    try do
      Loomkin.Repo.get(Loomkin.Accounts.User, user_id)
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp parse_mode("auto"), do: :auto
  defp parse_mode("commit"), do: :commit
  defp parse_mode("every_phase"), do: :every_phase
  defp parse_mode(_), do: :auto
end
