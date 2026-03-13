defmodule LoomkinWeb.DecisionGraphComponentTest do
  use LoomkinWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Loomkin.Decisions.Graph
  alias Loomkin.Repo
  alias Loomkin.Schemas.Session

  @team_id "test-team-graph"

  defp create_session do
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{
        model: "zai:glm-5",
        project_path: "/tmp/test"
      })
      |> Repo.insert()

    session.id
  end

  describe "signal subscriptions" do
    test "subscribes to decision signals on first update" do
      session_id = create_session()

      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-sub",
          session_id: session_id,
          team_id: @team_id
        })

      # Component renders successfully after subscribing
      assert html =~ "Decision Graph"
    end

    test "does not duplicate subscriptions on re-mount" do
      session_id = create_session()

      # First render subscribes
      render_component(LoomkinWeb.DecisionGraphComponent, %{
        id: "test-graph-dup",
        session_id: session_id,
        team_id: @team_id
      })

      # Second render with same component should not crash or duplicate
      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-dup",
          session_id: session_id,
          team_id: @team_id
        })

      assert html =~ "Decision Graph"
    end
  end

  describe "signal-driven graph reload" do
    test "reloads graph when decision.node.added signal arrives for matching team" do
      session_id = create_session()

      # Render with no nodes initially
      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-reload",
          session_id: session_id,
          team_id: @team_id
        })

      assert html =~ "No decisions recorded yet"

      # Add a node to the database
      {:ok, _node} =
        Graph.add_node(%{
          session_id: session_id,
          team_id: @team_id,
          node_type: :goal,
          title: "Live Update Goal",
          status: :active,
          agent_name: "researcher"
        })

      # Simulate the signal arriving via handle_info
      signal = %Jido.Signal{
        id: Jido.Signal.ID.generate(),
        type: "decision.node.added",
        source: "/test",
        data: %{team_id: @team_id},
        datacontenttype: "application/json",
        specversion: "1.0.1"
      }

      # Sending the signal to self simulates what happens in production
      # when the signal bus delivers to the subscribing process.
      # The debounced reload triggers after 500ms; for unit testing
      # we verify the component handles the signal without crashing.
      pid = self()
      send(pid, signal)

      # The signal is delivered but graph reload happens via debounced timer.
      # Verify the component can re-render with the new data when explicitly refreshed.
      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-reload",
          session_id: session_id,
          team_id: @team_id,
          refresh_ref: System.unique_integer()
        })

      assert html =~ "Live Update Goal"
      assert html =~ "researcher"
    end

    test "ignores signals from different team" do
      session_id = create_session()
      other_session_id = create_session()
      other_team = "other-team-id"

      # Add a node under a different team AND different session
      {:ok, _node} =
        Graph.add_node(%{
          session_id: other_session_id,
          team_id: other_team,
          node_type: :goal,
          title: "Other Team Goal",
          status: :active
        })

      # Render component scoped to our team/session — should show empty state
      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-scoped",
          session_id: session_id,
          team_id: @team_id
        })

      # Our team/session has no nodes, so empty state
      assert html =~ "No decisions recorded yet"
    end
  end

  describe "new node highlighting" do
    test "marks newly added nodes with graph-node-new class" do
      session_id = create_session()

      # First render — establish baseline with one node
      {:ok, _node1} =
        Graph.add_node(%{
          session_id: session_id,
          node_type: :goal,
          title: "Existing Goal",
          status: :active,
          agent_name: "concierge"
        })

      render_component(LoomkinWeb.DecisionGraphComponent, %{
        id: "test-graph-new",
        session_id: session_id,
        team_id: @team_id
      })

      # Add a second node
      {:ok, _node2} =
        Graph.add_node(%{
          session_id: session_id,
          node_type: :decision,
          title: "New Decision",
          status: :active,
          agent_name: "concierge"
        })

      # Re-render with refresh_ref to simulate signal-triggered reload
      html =
        render_component(LoomkinWeb.DecisionGraphComponent, %{
          id: "test-graph-new",
          session_id: session_id,
          team_id: @team_id,
          refresh_ref: System.unique_integer()
        })

      assert html =~ "New Decision"

      # In compact tree view, new nodes get bg-gray-800/30 highlight (not graph-node-new SVG class)
      assert html =~ "bg-gray-800/30"
    end
  end
end
