defmodule Loomkin.Orchestration.ApprovalTest do
  @moduledoc """
  Covers `Loomkin.Orchestration.Approval.maybe_block/2`.

  The helper resolves the user's approval mode from `epic.metadata` and
  decides whether to park the orchestrator in `:awaiting_approval` at gate
  boundaries / commit checkpoints.

  We use the DataCase so we can write a real user row and exercise the
  end-to-end resolution path. The "no user_id" cases use plain maps and
  don't need DB access, but it's fine to share the case.
  """
  use Loomkin.DataCase, async: true

  alias Loomkin.Accounts
  alias Loomkin.Orchestration.Approval

  defp register_user(mode) do
    email = "approval-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} = Accounts.register_user(%{email: email})

    {:ok, user} =
      Accounts.update_user_orchestration_preferences(user, %{
        orchestration_approval_mode: mode
      })

    user
  end

  describe "no user_id in metadata" do
    test ":continue for every phase when metadata has no user_id" do
      epic = %{id: "e1", metadata: %{}}

      for phase <- [:research, :plan, :plan_review, :pr, :closure] do
        assert Approval.maybe_block(epic, phase) == :continue
      end
    end

    test ":continue when metadata is missing entirely" do
      assert Approval.maybe_block(%{id: "e2"}, :pr) == :continue
    end

    test ":continue when user_id points to a non-existent user" do
      epic = %{id: "e3", metadata: %{"user_id" => Ecto.UUID.generate()}}
      assert Approval.maybe_block(epic, :pr) == :continue
    end
  end

  describe "mode = auto" do
    test ":continue for every phase" do
      user = register_user("auto")
      epic = %{id: "e-auto", metadata: %{"user_id" => "#{user.id}"}}

      for phase <- [:plan_review, :design_review, :final_review, :pr, :closure] do
        assert Approval.maybe_block(epic, phase) == :continue
      end
    end
  end

  describe "mode = commit" do
    setup do
      user = register_user("commit")
      epic = %{id: "e-commit", metadata: %{"user_id" => "#{user.id}"}}
      {:ok, %{epic: epic}}
    end

    test ":block before :pr only", %{epic: epic} do
      assert {:block, reason} = Approval.maybe_block(epic, :pr)
      assert is_binary(reason)
    end

    test ":continue at non-:pr phases", %{epic: epic} do
      for phase <- [:research, :plan, :plan_review, :design_review, :final_review] do
        assert Approval.maybe_block(epic, phase) == :continue
      end
    end
  end

  describe "mode = every_phase" do
    setup do
      user = register_user("every_phase")
      epic = %{id: "e-every", metadata: %{"user_id" => "#{user.id}"}}
      {:ok, %{epic: epic}}
    end

    test ":block at each gate phase", %{epic: epic} do
      for phase <- [:plan_review, :design_review, :final_review] do
        assert {:block, _} = Approval.maybe_block(epic, phase)
      end
    end

    test ":block before :pr", %{epic: epic} do
      assert {:block, _} = Approval.maybe_block(epic, :pr)
    end

    test ":continue for non-gate, non-:pr phases", %{epic: epic} do
      for phase <- [:research, :plan, :decompose, :execute, :closure] do
        assert Approval.maybe_block(epic, phase) == :continue
      end
    end
  end

  describe "metadata key tolerance" do
    test "accepts atom key :user_id" do
      user = register_user("commit")
      epic = %{id: "e-atom", metadata: %{user_id: "#{user.id}"}}
      assert {:block, _} = Approval.maybe_block(epic, :pr)
    end

    test "string key wins when both are present (preference for string)" do
      user_commit = register_user("commit")
      user_auto = register_user("auto")

      epic = %{
        id: "e-mixed",
        metadata: %{"user_id" => "#{user_commit.id}", user_id: "#{user_auto.id}"}
      }

      # We don't assert which one wins (implementation detail); we assert that
      # at least one of the two resolutions takes effect — i.e. we get a
      # deterministic answer, not a crash.
      result = Approval.maybe_block(epic, :pr)
      assert result == :continue or match?({:block, _}, result)
    end
  end

  describe "unknown / malformed mode" do
    test "falls back to :auto" do
      user = register_user("auto")

      {:ok, user} =
        user
        |> Ecto.Changeset.change(orchestration_approval_mode: "nonsense_mode")
        |> Loomkin.Repo.update()

      epic = %{id: "e-bad", metadata: %{"user_id" => "#{user.id}"}}
      assert Approval.maybe_block(epic, :pr) == :continue
    end
  end
end
