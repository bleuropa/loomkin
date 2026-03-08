defmodule LoomkinWeb.TeamTreeComponentTest do
  use LoomkinWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "TeamTreeComponent" do
    test "component is hidden when team_tree is empty", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, LoomkinWeb.TeamTreeComponent,
          id: "team-tree-test",
          team_tree: %{},
          root_team_id: "root-team",
          active_team_id: "root-team",
          agent_counts: %{},
          team_names: %{}
        )

      refute has_element?(view, "button", "Teams")
    end

    test "component renders trigger button when sub-teams exist", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, LoomkinWeb.TeamTreeComponent,
          id: "team-tree-test",
          team_tree: %{"root-team" => ["child-team-1"]},
          root_team_id: "root-team",
          active_team_id: "root-team",
          agent_counts: %{"root-team" => 2, "child-team-1" => 1},
          team_names: %{"child-team-1" => "Research Team"}
        )

      assert has_element?(view, "button", "Teams")
    end

    test "toggle_tree opens and closes the dropdown", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, LoomkinWeb.TeamTreeComponent,
          id: "team-tree-test",
          team_tree: %{"root-team" => ["child-team-1"]},
          root_team_id: "root-team",
          active_team_id: "root-team",
          agent_counts: %{"root-team" => 2, "child-team-1" => 1},
          team_names: %{"child-team-1" => "Research Team"}
        )

      # dropdown should not be visible initially
      refute has_element?(view, "[phx-click-away]")

      # open the dropdown
      view |> element("button", "Teams") |> render_click()
      assert has_element?(view, "[phx-click-away]")

      # close the dropdown
      view |> element("[phx-click-away]") |> render_hook("close_tree", %{})
      refute has_element?(view, "[phx-click-away]")
    end

    test "selecting a tree node sends switch_team to parent", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, LoomkinWeb.TeamTreeComponent,
          id: "team-tree-test",
          team_tree: %{"root-team" => ["child-team-1"]},
          root_team_id: "root-team",
          active_team_id: "root-team",
          agent_counts: %{"root-team" => 2, "child-team-1" => 1},
          team_names: %{"child-team-1" => "Research Team"}
        )

      # open the dropdown first
      view |> element("button", "Teams") |> render_click()

      # click the child team node
      view
      |> element("[phx-click='select_team'][phx-value-team-id='child-team-1']")
      |> render_click()

      # dropdown should close
      refute has_element?(view, "[phx-click-away]")

      # parent (test process) should receive {:switch_team, team_id}
      assert_receive {:switch_team, "child-team-1"}
    end
  end
end
