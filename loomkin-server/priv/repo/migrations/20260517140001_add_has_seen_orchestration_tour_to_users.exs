defmodule Loomkin.Repo.Migrations.AddHasSeenOrchestrationTourToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :has_seen_orchestration_tour, :boolean, default: false, null: false
    end
  end
end
