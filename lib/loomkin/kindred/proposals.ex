defmodule Loomkin.Kindred.Proposals do
  @moduledoc "Manages kindred evolution proposals from reflection or users."

  import Ecto.Query

  alias Loomkin.Repo
  alias Loomkin.Schemas.KindredProposal

  def create_proposal(%{user: _user}, attrs) do
    %KindredProposal{}
    |> KindredProposal.changeset(attrs)
    |> Repo.insert()
  end

  def approve_proposal(%{user: user}, %KindredProposal{} = proposal) do
    proposal
    |> KindredProposal.changeset(%{
      status: :approved,
      reviewed_by: user.id,
      reviewed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  def reject_proposal(%{user: user}, %KindredProposal{} = proposal, notes) do
    proposal
    |> KindredProposal.changeset(%{
      status: :rejected,
      reviewed_by: user.id,
      reviewed_at: DateTime.utc_now(),
      review_notes: notes
    })
    |> Repo.update()
  end

  def apply_proposal(%{user: _user} = scope, %KindredProposal{status: :approved} = proposal) do
    kindred = Loomkin.Kindred.get_kindred!(proposal.kindred_id)
    changes = proposal.changes || %{}

    Repo.transaction(fn ->
      # Apply item changes from the proposal
      apply_item_changes(scope, kindred, changes)

      # Increment version
      {:ok, _kindred} = Loomkin.Kindred.publish_kindred(scope, kindred)

      # Mark proposal as applied
      {:ok, applied} =
        proposal
        |> KindredProposal.changeset(%{status: :applied})
        |> Repo.update()

      applied
    end)
  end

  def apply_proposal(_scope, _proposal), do: {:error, :not_approved}

  def list_pending_proposals(kindred_id) do
    KindredProposal
    |> where([p], p.kindred_id == ^kindred_id and p.status == :pending)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  def list_proposals_for_kindred(kindred_id) do
    KindredProposal
    |> where([p], p.kindred_id == ^kindred_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  def get_proposal(id), do: Repo.get(KindredProposal, id)

  # --- Private ---

  defp apply_item_changes(scope, kindred, changes) do
    # Apply kin_config updates
    for %{"type" => "kin_config_update", "target" => name} = change <-
          Map.get(changes, "recommendations", []) do
      items = Loomkin.Kindred.list_items(kindred)

      case Enum.find(items, fn i -> i.item_type == :kin_config && i.content["name"] == name end) do
        nil ->
          # Add new item
          Loomkin.Kindred.add_item(scope, kindred, %{
            item_type: :kin_config,
            content: Map.get(change, "changes", %{}) |> Map.put("name", name)
          })

        item ->
          # Update existing item
          new_content = Map.merge(item.content, Map.get(change, "changes", %{}))
          Loomkin.Kindred.update_item(scope, item, %{content: new_content})
      end
    end

    # Apply skill additions
    for %{"type" => "skill_addition"} = change <- Map.get(changes, "recommendations", []) do
      Loomkin.Kindred.add_item(scope, kindred, %{
        item_type: :skill_ref,
        content: %{
          "skill_name" => change["name"],
          "inline_body" => change["body"]
        }
      })
    end

    :ok
  end
end
