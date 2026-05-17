defmodule LoomkinWeb.OrchestrationShowSteeringTest do
  @moduledoc """
  r14 — exercises the in-flight steering controls surfaced on the
  per-epic LiveView (Pause / Cancel / Resume / Approve / Reject) and
  the index page's inline action buttons.

  We don't spawn a real IssueOrchestrator for these tests — the
  underlying `SwarmCoordinator.<verb>/2` calls return
  `{:error, :not_found}` when no orchestrator is registered for the
  epic, and the LV's handle_event clauses ignore the return value.
  The point of these tests is that the buttons exist, fire the right
  events, and don't crash.
  """
  use LoomkinWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Loomkin.Orchestration.Context

  setup :register_and_log_in_user

  defp create_epic!(attrs) do
    {:ok, epic} =
      Context.create_epic(
        Map.merge(
          %{
            title: "Steering test epic",
            spec: "spec body",
            priority: 2
          },
          attrs
        )
      )

    epic
  end

  describe "OrchestrationShowLive — steering action row" do
    test "renders Pause and Cancel when epic is in_progress", %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan"})

      {:ok, view, html} = live(conn, "/orchestration/#{epic.id}")

      assert html =~ "Pause"
      assert html =~ "Cancel"

      # phx-click for these buttons exists in the page-level action row
      assert has_element?(
               view,
               ~s|[data-testid="orchestration-show-actions"] button[phx-click="pause"][phx-value-id="#{epic.id}"]|
             )

      assert has_element?(
               view,
               ~s|[data-testid="orchestration-show-actions"] button[phx-click="cancel"][phx-value-id="#{epic.id}"]|
             )
    end

    test "Pause click is handled gracefully when no orchestrator is registered",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan"})

      {:ok, view, _html} = live(conn, "/orchestration/#{epic.id}")

      # Click Pause — the handler dispatches to SwarmCoordinator.pause/2 which
      # returns {:error, :not_found} (no registered orchestrator). The LV should
      # render without crashing. We target the show-page action row (not the
      # live_component duplicate) via the wrapper testid.
      view
      |> element(~s|[data-testid="orchestration-show-actions"] button[phx-click="pause"]|)
      |> render_click()

      # Still mounted (didn't crash).
      assert render(view) =~ epic.title
    end

    test "Cancel click is handled gracefully when no orchestrator is registered",
         %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, current_phase: "plan"})

      {:ok, view, _html} = live(conn, "/orchestration/#{epic.id}")

      view
      |> element(~s|[data-testid="orchestration-show-actions"] button[phx-click="cancel"]|)
      |> render_click()

      assert render(view) =~ epic.title
    end

    test "Resume button shows up only when the epic.metadata.paused flag is true",
         %{conn: conn} do
      paused = create_epic!(%{status: :in_progress, metadata: %{"paused" => true}})

      {:ok, view, html} = live(conn, "/orchestration/#{paused.id}")

      assert html =~ "Resume"

      assert has_element?(
               view,
               ~s|[data-testid="orchestration-show-actions"] button[phx-click="resume"]|
             )

      view
      |> element(~s|[data-testid="orchestration-show-actions"] button[phx-click="resume"]|)
      |> render_click()

      assert render(view) =~ paused.title
    end

    test "approval prompt appears when status is awaiting_human + approval flag",
         %{conn: conn} do
      epic =
        create_epic!(%{
          status: :awaiting_human,
          metadata: %{"approval_reason" => "Approve before opening PR"}
        })

      {:ok, view, html} = live(conn, "/orchestration/#{epic.id}")

      assert html =~ "Approval requested"
      assert html =~ "Approve before opening PR"

      assert has_element?(
               view,
               ~s|[data-testid="orchestration-approval-prompt"] button[phx-click="approve"]|
             )

      assert has_element?(
               view,
               ~s|[data-testid="orchestration-approval-prompt"] button[phx-click="reject"]|
             )

      view
      |> element(~s|[data-testid="orchestration-approval-prompt"] button[phx-click="approve"]|)
      |> render_click()

      view
      |> element(~s|[data-testid="orchestration-approval-prompt"] button[phx-click="reject"]|)
      |> render_click()

      assert render(view) =~ epic.title
    end

    test "no steering buttons for terminal :closed status", %{conn: conn} do
      epic = create_epic!(%{status: :closed})

      {:ok, _view, html} = live(conn, "/orchestration/#{epic.id}")

      refute html =~ ~s|phx-click="pause"|
      refute html =~ ~s|phx-click="cancel"|
      refute html =~ ~s|phx-click="resume"|
      refute html =~ ~s|phx-click="approve"|
    end

    test "cancelled epics render a 'cancelled' badge and no Cancel button",
         %{conn: conn} do
      epic = create_epic!(%{status: :cancelled})

      {:ok, _view, html} = live(conn, "/orchestration/#{epic.id}")

      assert html =~ "cancelled"
      refute html =~ ~s|phx-click="cancel"|
    end
  end

  describe "OrchestrationIndexLive — inline steering" do
    test "renders Pause and Cancel for active epics", %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, title: "Index pause test"})

      {:ok, view, html} = live(conn, "/orchestration")

      assert html =~ "Index pause test"
      assert html =~ "Pause"
      assert has_element?(view, ~s|button[phx-click="pause"][phx-value-id="#{epic.id}"]|)
      assert has_element?(view, ~s|button[phx-click="cancel"][phx-value-id="#{epic.id}"]|)
    end

    test "clicking Pause on the index does not crash", %{conn: conn} do
      epic = create_epic!(%{status: :in_progress, title: "Index pause click"})

      {:ok, view, _html} = live(conn, "/orchestration")

      view
      |> element(~s|button[phx-click="pause"][phx-value-id="#{epic.id}"]|)
      |> render_click()

      assert render(view) =~ "Index pause click"
    end

    test "Resume replaces Pause when metadata.paused=true on the index", %{conn: conn} do
      epic =
        create_epic!(%{
          status: :in_progress,
          title: "Index resume test",
          metadata: %{"paused" => true}
        })

      {:ok, view, _html} = live(conn, "/orchestration")

      assert has_element?(view, ~s|button[phx-click="resume"][phx-value-id="#{epic.id}"]|)
      refute has_element?(view, ~s|button[phx-click="pause"][phx-value-id="#{epic.id}"]|)
    end

    test "no inline action row for :closed epics", %{conn: conn} do
      epic = create_epic!(%{status: :closed, title: "Closed shouldn't show actions"})

      {:ok, view, _html} = live(conn, "/orchestration")

      refute has_element?(view, ~s|button[phx-click="pause"][phx-value-id="#{epic.id}"]|)
      refute has_element?(view, ~s|button[phx-click="cancel"][phx-value-id="#{epic.id}"]|)
    end
  end

  describe "User settings — orchestration approval mode" do
    test "PUT /users/settings update_orchestration_preferences persists the mode",
         %{conn: conn, user: user} do
      assert user.orchestration_approval_mode == "auto"

      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_orchestration_preferences",
          "user" => %{"orchestration_approval_mode" => "commit"}
        })

      assert redirected_to(conn) == ~p"/users/settings"

      reloaded = Loomkin.Repo.get!(Loomkin.Accounts.User, user.id)
      assert reloaded.orchestration_approval_mode == "commit"
    end

    test "every_phase is a permitted value", %{conn: conn, user: user} do
      put(conn, ~p"/users/settings", %{
        "action" => "update_orchestration_preferences",
        "user" => %{"orchestration_approval_mode" => "every_phase"}
      })

      reloaded = Loomkin.Repo.get!(Loomkin.Accounts.User, user.id)
      assert reloaded.orchestration_approval_mode == "every_phase"
    end

    test "rejects unknown values without persisting", %{conn: conn, user: user} do
      put(conn, ~p"/users/settings", %{
        "action" => "update_orchestration_preferences",
        "user" => %{"orchestration_approval_mode" => "yolo"}
      })

      reloaded = Loomkin.Repo.get!(Loomkin.Accounts.User, user.id)
      assert reloaded.orchestration_approval_mode == "auto"
    end

    test "GET /users/settings renders the orchestration approval mode form",
         %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ "Orchestration approval"
      assert response =~ "Approve at commit"
      assert response =~ "Approve at every phase"
      assert response =~ ~s|name="action" value="update_orchestration_preferences"|
    end
  end
end
