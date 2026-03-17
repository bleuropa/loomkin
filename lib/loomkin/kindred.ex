defmodule Loomkin.Kindred do
  @moduledoc "Context module for managing kindred bundles and their items."

  import Ecto.Query

  alias Loomkin.Repo
  alias Loomkin.Schemas.Kindred
  alias Loomkin.Schemas.KindredItem

  # --- Kindred CRUD ---

  def create_kindred(%{user: user}, attrs) when not is_nil(user) do
    attrs = Map.put_new(attrs, :user_id, user.id)

    %Kindred{}
    |> Kindred.changeset(attrs)
    |> Repo.insert()
  end

  def update_kindred(%{user: _user}, %Kindred{} = kindred, attrs) do
    kindred
    |> Kindred.changeset(attrs)
    |> Repo.update()
  end

  def publish_kindred(%{user: _user}, %Kindred{} = kindred) do
    kindred
    |> Kindred.changeset(%{
      status: :active,
      version: kindred.version + 1
    })
    |> Repo.update()
  end

  def archive_kindred(%{user: _user}, %Kindred{} = kindred) do
    kindred
    |> Kindred.changeset(%{status: :archived})
    |> Repo.update()
  end

  def get_kindred(id), do: Repo.get(Kindred, id)

  def get_kindred!(id), do: Repo.get!(Kindred, id)

  # --- Items ---

  def add_item(%{user: _user}, %Kindred{} = kindred, attrs) do
    max_position =
      KindredItem
      |> where([i], i.kindred_id == ^kindred.id)
      |> select([i], max(i.position))
      |> Repo.one() || -1

    attrs =
      attrs
      |> Map.put(:kindred_id, kindred.id)
      |> Map.put_new(:position, max_position + 1)

    %KindredItem{}
    |> KindredItem.changeset(attrs)
    |> Repo.insert()
  end

  def remove_item(%{user: _user}, %Kindred{} = _kindred, item_id) do
    case Repo.get(KindredItem, item_id) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item)
    end
  end

  def update_item(%{user: _user}, %KindredItem{} = item, attrs) do
    item
    |> KindredItem.changeset(attrs)
    |> Repo.update()
  end

  def list_items(%Kindred{} = kindred) do
    KindredItem
    |> where([i], i.kindred_id == ^kindred.id)
    |> order_by([i], asc: i.position)
    |> Repo.all()
  end

  # --- Listing ---

  def list_user_kindreds(user) do
    Kindred
    |> where([k], k.user_id == ^user.id)
    |> order_by([k], desc: k.updated_at)
    |> Repo.all()
  end

  def list_org_kindreds(org) do
    Kindred
    |> where([k], k.organization_id == ^org.id)
    |> order_by([k], desc: k.updated_at)
    |> Repo.all()
  end

  def active_kindred_for_org(org) do
    Kindred
    |> where([k], k.organization_id == ^org.id and k.status == :active)
    |> order_by([k], desc: k.version)
    |> limit(1)
    |> preload(:items)
    |> Repo.one()
  end

  def active_kindred_for_user(user) do
    Kindred
    |> where([k], k.user_id == ^user.id and k.status == :active)
    |> order_by([k], desc: k.version)
    |> limit(1)
    |> preload(:items)
    |> Repo.one()
  end
end
