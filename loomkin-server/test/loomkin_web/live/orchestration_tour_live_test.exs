defmodule LoomkinWeb.OrchestrationTourLiveTest do
  @moduledoc """
  Covers the read-only `/orchestration/tour` walkthrough page and its
  "Dismiss permanently" button, which marks the current user as having
  seen the orchestration tour.
  """

  use LoomkinWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Loomkin.Accounts
  alias Loomkin.Repo

  setup :register_and_log_in_user

  test "GET /orchestration/tour renders all nine phase personas", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/orchestration/tour")

    assert html =~ "Loomkin orchestration"
    assert html =~ "The 9 phases"

    # Each canonical persona name should appear.
    for name <- [
          "Researcher",
          "Planner",
          "Plan Council",
          "Design Council",
          "Decomposer",
          "Executor",
          "Adversarial Reviewer",
          "PR Author",
          "Curator"
        ] do
      assert html =~ name, "expected persona #{name} in rendered HTML"
    end
  end

  test "GET /orchestration/tour describes the work-unit inner pipeline", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/orchestration/tour")

    assert html =~ "Inside each work unit"
    # The four work-unit phases must each appear by name.
    for name <- ["Coder", "Validator", "DoD Verifier", "Committer"] do
      assert html =~ name, "expected work-unit persona #{name} in rendered HTML"
    end
  end

  test "GET /orchestration/tour exposes the steering keys", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/orchestration/tour")

    assert html =~ "You stay in control"
    assert html =~ "pause an in-flight epic"
    assert html =~ "cancel and clean up the worktree"
    assert html =~ "resume from pause"
  end

  test "'Dismiss permanently' marks the current user as having seen the tour", %{
    conn: conn,
    user: user
  } do
    refute user.has_seen_orchestration_tour

    {:ok, view, _html} = live(conn, "/orchestration/tour")

    # Clicking the dismiss button redirects to /orchestration and persists
    # the boolean on the user row.
    assert {:error, {:live_redirect, %{to: "/orchestration"}}} =
             view |> element("button[phx-click='dismiss']") |> render_click()

    refreshed = Repo.reload!(user)
    assert refreshed.has_seen_orchestration_tour == true
  end

  test "Accounts.mark_orchestration_tour_seen/1 is idempotent" do
    user = %Loomkin.Accounts.User{
      id: Ecto.UUID.generate(),
      email: "u#{System.unique_integer()}@e.com",
      has_seen_orchestration_tour: true
    }

    # Already-seen → returns the user without hitting the DB.
    assert {:ok, ^user} = Accounts.mark_orchestration_tour_seen(user)
  end
end
