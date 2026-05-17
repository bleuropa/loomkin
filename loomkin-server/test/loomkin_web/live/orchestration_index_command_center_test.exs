defmodule LoomkinWeb.OrchestrationIndexCommandCenterTest do
  @moduledoc """
  Command-center layout tests for `LoomkinWeb.OrchestrationIndexLive`.

  Covers:
    * Empty state — no active epics, no recent epics
    * Single active epic — persona, phase dots, cost/eta placeholders,
      per-row Pause / Cancel / Open buttons
    * Multi-active — all in-flight epics render in the active stream
    * Bulk selection — toolbar appears, bulk pause/cancel handlers run
      without crashing when no orchestrator is registered
    * Recent — closed/failed/cancelled epics from the last 30 days
      surface in the recent section
    * Recent excludes anything older than 30 days
    * Stream insert on PubSub — broadcasting a status flip transitions
      the row from active to recent without a full re-query
    * Bulk select via phx-change populates the toolbar
  """
  use LoomkinWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]

  alias Loomkin.Orchestration.Context
  alias Loomkin.Orchestration.Schema.Epic
  alias Loomkin.Repo

  @topic "orchestration.epic"

  setup :register_and_log_in_user

  defp create_epic!(attrs) do
    {:ok, epic} =
      Context.create_epic(
        Map.merge(
          %{
            title: "command-center test epic",
            spec: "spec body",
            priority: 2
          },
          attrs
        )
      )

    epic
  end

  defp force_inserted_at!(%Epic{id: id}, %DateTime{} = at) do
    {1, _} = Repo.update_all(from(e in Epic, where: e.id == ^id), set: [inserted_at: at])
    Repo.get!(Epic, id)
  end

  describe "empty state" do
    test "renders both section headers and empty copy", %{conn: conn} do
      {:ok, view, html} = live(conn, "/orchestration")

      assert html =~ "Orchestration"
      assert html =~ "Active epics"
      assert html =~ "Recent"
      assert html =~ "Start a new epic"
      assert has_element?(view, "[data-testid=orchestration-active-empty]")
      assert has_element?(view, "[data-testid=orchestration-recent-empty]")
    end

    test "active count badge reads 0", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/orchestration")

      assert has_element?(view, "[data-testid=orchestration-active-count]", "0 in flight")
    end
  end

  describe "active stream" do
    test "renders a single active epic with persona, status, and actions",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "research", title: "epic-A"})

      {:ok, view, html} = live(conn, "/orchestration")

      assert html =~ "epic-A"
      assert html =~ "Researcher"
      assert has_element?(view, "[data-testid=orchestration-active-count]", "1 in flight")

      # Action row exists for this epic
      assert has_element?(
               view,
               ~s|[data-testid="orchestration-index-actions-#{epic.id}"] button[phx-click="pause"][phx-value-id="#{epic.id}"]|
             )

      assert has_element?(
               view,
               ~s|[data-testid="orchestration-index-actions-#{epic.id}"] button[phx-click="cancel"][phx-value-id="#{epic.id}"]|
             )

      # Open link points at the show route
      assert has_element?(view, ~s|a[href="/orchestration/#{epic.id}"]|, "Open")

      # Cost + ETA placeholders render the em-dash when no metrics exist
      assert has_element?(view, "[data-testid=\"epic-#{epic.id}-cost\"]", "—")
      assert has_element?(view, "[data-testid=\"epic-#{epic.id}-eta\"]", "—")
    end

    test "renders multiple active epics", %{conn: conn} do
      _a = create_epic!(%{status: :in_progress, current_phase: "research", title: "alpha"})
      _b = create_epic!(%{status: :awaiting_human, current_phase: "plan", title: "beta"})
      _c = create_epic!(%{status: :pending, current_phase: nil, title: "gamma"})

      {:ok, view, html} = live(conn, "/orchestration")

      assert html =~ "alpha"
      assert html =~ "beta"
      assert html =~ "gamma"
      assert has_element?(view, "[data-testid=orchestration-active-count]", "3 in flight")
    end

    test "Pause click is handled gracefully when no orchestrator is registered",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan"})

      {:ok, view, _html} = live(conn, "/orchestration")

      view
      |> element(
        ~s|[data-testid="orchestration-index-actions-#{epic.id}"] button[phx-click="pause"]|
      )
      |> render_click()

      # Still mounted (didn't crash) and the row is still visible
      assert render(view) =~ epic.title
    end
  end

  describe "recent list" do
    test "shows closed/failed/cancelled epics from the last 30 days", %{conn: conn} do
      _closed = create_epic!(%{status: :closed, title: "closed-one"})
      _failed = create_epic!(%{status: :failed, title: "failed-one"})
      _cancelled = create_epic!(%{status: :cancelled, title: "cancelled-one"})

      # An active epic should NOT appear in the recent list.
      _active = create_epic!(%{status: :in_progress, title: "active-one"})

      {:ok, view, html} = live(conn, "/orchestration")

      assert html =~ "closed-one"
      assert html =~ "failed-one"
      assert html =~ "cancelled-one"

      # Active epic shows in active section, NOT recent
      assert html =~ "active-one"

      assert has_element?(view, "[data-testid=orchestration-recent-section]")
      refute has_element?(view, "[data-testid=orchestration-recent-empty]")
    end

    test "excludes epics older than 30 days", %{conn: conn} do
      old =
        create_epic!(%{status: :closed, title: "old-closed-epic"})
        |> force_inserted_at!(DateTime.utc_now() |> DateTime.add(-31, :day))

      {:ok, _view, html} = live(conn, "/orchestration")

      refute html =~ "old-closed-epic"
      _ = old
    end
  end

  describe "bulk selection" do
    test "selecting an epic via phx-change reveals the bulk toolbar",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan", title: "bulk-target"})

      {:ok, view, _html} = live(conn, "/orchestration")

      # Toolbar hidden until something is selected.
      refute has_element?(view, "[data-testid=orchestration-bulk-toolbar]")

      view
      |> form("form[phx-change=select_changed]", %{"selected_ids" => [epic.id]})
      |> render_change()

      assert has_element?(view, "[data-testid=orchestration-bulk-toolbar]", "1 selected")
    end

    test "bulk pause / cancel handlers run without crashing", %{conn: conn} do
      e1 = create_epic!(%{status: :in_progress, current_phase: "plan", title: "bp-1"})
      e2 = create_epic!(%{status: :in_progress, current_phase: "plan", title: "bp-2"})

      {:ok, view, _html} = live(conn, "/orchestration")

      view
      |> form("form[phx-change=select_changed]", %{"selected_ids" => [e1.id, e2.id]})
      |> render_change()

      assert has_element?(view, "[data-testid=orchestration-bulk-toolbar]", "2 selected")

      # Trigger bulk pause — SwarmCoordinator returns {:error, :not_found}
      # since no real orchestrator is running, but the LV should not crash.
      view |> element("button[phx-click=bulk_pause]") |> render_click()

      # Selection is cleared after the bulk action.
      refute has_element?(view, "[data-testid=orchestration-bulk-toolbar]")

      # Re-select and try bulk_cancel.
      view
      |> form("form[phx-change=select_changed]", %{"selected_ids" => [e1.id, e2.id]})
      |> render_change()

      view |> element("button[phx-click=bulk_cancel]") |> render_click()

      refute has_element?(view, "[data-testid=orchestration-bulk-toolbar]")

      # Page is still alive after both bulk actions
      assert render(view) =~ "Active epics"
    end
  end

  describe "PubSub-driven stream updates" do
    test "broadcasting a status flip moves the row from active to recent",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan", title: "flips-status"})

      {:ok, view, html} = live(conn, "/orchestration")
      assert html =~ "flips-status"
      assert has_element?(view, "[data-testid=orchestration-active-count]", "1 in flight")

      # Flip the persisted status to :closed, then broadcast — the LV should
      # remove the row from the active stream and refresh the recent list
      # without us re-querying everything.
      {1, _} =
        Repo.update_all(
          from(e in Epic, where: e.id == ^epic.id),
          set: [status: :closed]
        )

      Phoenix.PubSub.broadcast(
        Loomkin.PubSub,
        @topic,
        {@topic, %{epic_id: epic.id, event: :closed}}
      )

      # Give the LV a tick to handle the message.
      _ = render(view)

      # Active count is now 0; row still surfaces in the recent section.
      assert has_element?(view, "[data-testid=orchestration-active-count]", "0 in flight")
      assert has_element?(view, "[data-testid=orchestration-recent-section]", "flips-status")
    end

    test "broadcasting an unrelated message does not crash the LV",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/orchestration")

      Phoenix.PubSub.broadcast(
        Loomkin.PubSub,
        @topic,
        {@topic, :some_unstructured_payload}
      )

      assert render(view) =~ "Active epics"
    end
  end
end
