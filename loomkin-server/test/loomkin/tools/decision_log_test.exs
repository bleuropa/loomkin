defmodule Loomkin.Tools.DecisionLogTest do
  use Loomkin.DataCase, async: false

  alias Loomkin.Tools.DecisionLog
  alias Loomkin.Decisions.Graph
  alias Loomkin.Schemas.Session

  defp create_session do
    %Session{}
    |> Session.changeset(%{model: "test-model", project_path: "/tmp/test"})
    |> Repo.insert!()
  end

  test "action metadata is correct" do
    assert DecisionLog.name() == "decision_log"
    assert is_binary(DecisionLog.description())
  end

  test "logs a simple decision node" do
    params = %{"node_type" => "goal", "title" => "Build auth system"}
    assert {:ok, %{result: msg}} = DecisionLog.run(params, %{})
    assert msg =~ "goal: Build auth system"
    assert msg =~ "id:"
  end

  test "logs a node with parent edge" do
    {:ok, parent} = Graph.add_node(%{node_type: :goal, title: "Parent"})

    params = %{
      "node_type" => "action",
      "title" => "Implement login",
      "parent_id" => parent.id,
      "edge_type" => "leads_to"
    }

    assert {:ok, %{result: msg}} = DecisionLog.run(params, %{})
    assert msg =~ "linked to #{parent.id} via leads_to"
  end

  test "logs node with description and confidence" do
    params = %{
      "node_type" => "decision",
      "title" => "Use JWT",
      "description" => "JWT for stateless auth",
      "confidence" => 85
    }

    assert {:ok, %{result: msg}} = DecisionLog.run(params, %{})
    assert msg =~ "decision: Use JWT"
  end

  test "reuses an existing active goal for the same team" do
    team_id = Ecto.UUID.generate()
    session = create_session()

    params = %{"node_type" => "goal", "title" => "Build auth system"}
    context = %{team_id: team_id, session_id: session.id}

    assert {:ok, %{result: first_msg}} = DecisionLog.run(params, context)
    assert first_msg =~ "Logged goal: Build auth system"

    assert {:ok, %{result: second_msg}} = DecisionLog.run(params, context)
    assert second_msg =~ "Reused active goal: Build auth system"

    nodes =
      Graph.list_nodes(
        node_type: :goal,
        status: :active,
        title: "Build auth system",
        team_id: team_id
      )

    assert length(nodes) == 1
  end

  test "returns error for invalid node_type" do
    params = %{"node_type" => "invalid", "title" => "Test"}

    assert {:error, msg} = DecisionLog.run(params, %{})
    assert msg =~ "Invalid node_type"
  end
end
