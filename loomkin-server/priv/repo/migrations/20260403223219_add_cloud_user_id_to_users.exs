defmodule Loomkin.Repo.Migrations.AddCloudUserIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :cloud_user_id, :string
    end

    create unique_index(:users, [:cloud_user_id])
  end
end
