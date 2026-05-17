defmodule Loomkin.Repo.Migrations.AddOrchestrationApprovalModeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :orchestration_approval_mode, :string, default: "auto", null: false
    end
  end
end
