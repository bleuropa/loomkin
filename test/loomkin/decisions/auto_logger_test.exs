defmodule Loomkin.Decisions.AutoLoggerTest do
  use Loomkin.DataCase, async: false

  alias Loomkin.Decisions.{AutoLogger, Graph}

  setup do
    team_id = Ecto.UUID.generate()

    {:ok, _ref} = Loomkin.Teams.TableRegistry.create_table(team_id)
    {:ok, pid} = start_supervised({AutoLogger, team_id: team_id})

    on_exit(fn ->
      Loomkin.Teams.TableRegistry.delete_table(team_id)
    end)

    %{team_id: team_id, logger_pid: pid}
  end

  defp send_status(pid, agent_name, team_id, status) do
    sig =
      Loomkin.Signals.Agent.Status.new!(%{
        agent_name: agent_name,
        team_id: team_id,
        status: status
      })

    send(pid, {:signal, sig})
  end

  defp send_task_assigned(pid, task_id, agent_name, team_id) do
    sig =
      Loomkin.Signals.Team.TaskAssigned.new!(%{
        task_id: task_id,
        agent_name: agent_name,
        team_id: team_id
      })

    send(pid, {:signal, sig})
  end

  defp send_task_completed(pid, task_id, owner, team_id) do
    sig =
      Loomkin.Signals.Team.TaskCompleted.new!(%{task_id: task_id, owner: owner, team_id: team_id})

    send(pid, {:signal, sig})
  end

  defp send_task_failed(pid, task_id, owner, team_id) do
    sig =
      Loomkin.Signals.Team.TaskFailed.new!(%{task_id: task_id, owner: owner, team_id: team_id})

    send(pid, {:signal, sig})
  end

  describe "agent_status events" do
    test "logs action node on first :working status", %{team_id: team_id, logger_pid: pid} do
      send_status(pid, "alice", team_id, :working)
      Process.sleep(200)

      nodes = Graph.list_nodes(node_type: :action)
      assert length(nodes) == 1
      assert hd(nodes).title == "Agent alice joined team"
      assert hd(nodes).metadata["auto_logged"] == true
      assert hd(nodes).metadata["team_id"] == team_id
    end

    test "only logs once per agent (deduplicates)", %{team_id: team_id, logger_pid: pid} do
      send_status(pid, "bob", team_id, :working)
      Process.sleep(200)
      send_status(pid, "bob", team_id, :working)
      Process.sleep(200)

      nodes = Graph.list_nodes(node_type: :action)
      assert length(nodes) == 1
    end

    test "logs separate nodes for different agents", %{team_id: team_id, logger_pid: pid} do
      send_status(pid, "alice", team_id, :working)
      send_status(pid, "bob", team_id, :working)
      Process.sleep(200)

      nodes = Graph.list_nodes(node_type: :action)
      assert length(nodes) == 2
      titles = Enum.map(nodes, & &1.title)
      assert "Agent alice joined team" in titles
      assert "Agent bob joined team" in titles
    end

    test "ignores non-working statuses", %{team_id: team_id, logger_pid: pid} do
      send_status(pid, "carol", team_id, :idle)
      Process.sleep(200)

      assert Graph.list_nodes(node_type: :action) == []
    end
  end

  describe "task events" do
    test "task_assigned creates action node", %{team_id: team_id, logger_pid: pid} do
      {:ok, task} = create_task(team_id, "Implement feature X")

      send_task_assigned(pid, task.id, "alice", team_id)
      Process.sleep(200)

      nodes = Graph.list_nodes(node_type: :action)
      assert length(nodes) == 1
      node = hd(nodes)
      assert node.title =~ "Task assigned: Implement feature X"
      assert node.title =~ "alice"
      assert node.metadata["auto_logged"] == true
    end

    test "task_completed creates outcome node with edge from task action", %{
      team_id: team_id,
      logger_pid: pid
    } do
      {:ok, task} = create_task(team_id, "Fix bug Y")

      send_task_assigned(pid, task.id, "bob", team_id)
      Process.sleep(200)

      send_task_completed(pid, task.id, "bob", team_id)
      Process.sleep(200)

      outcomes = Graph.list_nodes(node_type: :outcome)
      assert length(outcomes) == 1
      outcome = hd(outcomes)
      assert outcome.title == "Completed: Fix bug Y"

      edges = Graph.list_edges(edge_type: :leads_to, to_node_id: outcome.id)
      assert length(edges) >= 1

      action = hd(Graph.list_nodes(node_type: :action))
      assert Enum.any?(edges, &(&1.from_node_id == action.id))
    end

    test "task_failed creates outcome node", %{team_id: team_id, logger_pid: pid} do
      {:ok, task} = create_task(team_id, "Deploy service")

      send_task_assigned(pid, task.id, "carol", team_id)
      Process.sleep(200)

      send_task_failed(pid, task.id, "carol", team_id)
      Process.sleep(200)

      outcomes = Graph.list_nodes(node_type: :outcome)
      assert length(outcomes) == 1
      outcome = hd(outcomes)
      assert outcome.title =~ "Failed: Deploy service"
    end
  end

  describe "keeper_created events" do
    test "creates observation node with keeper_id in metadata", %{
      team_id: team_id,
      logger_pid: pid
    } do
      keeper_id = Ecto.UUID.generate()

      sig =
        Loomkin.Signals.Context.KeeperCreated.new!(%{
          id: keeper_id,
          topic: "auth-research",
          source: "alice",
          team_id: team_id
        })

      send(pid, {:signal, sig})

      Process.sleep(200)

      nodes = Graph.list_nodes(node_type: :observation)
      assert length(nodes) == 1
      node = hd(nodes)
      assert node.title == "Context offloaded: auth-research"
      assert node.metadata["keeper_id"] == keeper_id
      assert node.metadata["auto_logged"] == true
    end
  end

  describe "context_offloaded events" do
    test "are skipped (redundant with keeper_created)", %{team_id: team_id, logger_pid: pid} do
      sig = Loomkin.Signals.Context.Offloaded.new!(%{agent_name: "alice", team_id: team_id})
      send(pid, {:signal, sig})
      Process.sleep(200)

      assert Graph.list_nodes() == []
    end
  end

  describe "active goal linking" do
    test "edges action nodes to active goal when one exists", %{team_id: team_id, logger_pid: pid} do
      {:ok, goal} =
        Graph.add_node(%{
          node_type: :goal,
          title: "Ship v1",
          status: :active,
          metadata: %{"team_id" => team_id}
        })

      send_status(pid, "alice", team_id, :working)
      Process.sleep(200)

      action = hd(Graph.list_nodes(node_type: :action))
      edges = Graph.list_edges(from_node_id: goal.id, edge_type: :leads_to)
      assert Enum.any?(edges, &(&1.to_node_id == action.id))
    end
  end

  describe "tool event filtering" do
    test "low-value tools are completely skipped", %{team_id: team_id, logger_pid: pid} do
      send_tool_executing(pid, "alice", "directory_list", team_id)
      Process.sleep(50)
      send_tool_complete(pid, "alice", "directory_list", team_id)
      Process.sleep(200)

      assert Graph.list_nodes(node_type: :action) == []
      assert Graph.list_nodes(node_type: :outcome) == []
    end

    test "multiple low-value tools produce zero nodes", %{team_id: team_id, logger_pid: pid} do
      for tool <- ~w(file_read content_search query_backlog decision_query search_keepers) do
        send_tool_executing(pid, "alice", tool, team_id)
        send_tool_complete(pid, "alice", tool, team_id)
      end

      Process.sleep(200)

      assert Graph.list_nodes() == []
    end

    test "meaningful tools still produce nodes", %{team_id: team_id, logger_pid: pid} do
      send_tool_executing(pid, "alice", "file_write", team_id)
      Process.sleep(50)
      send_tool_complete(pid, "alice", "file_write", team_id)
      Process.sleep(200)

      # Fast completion — should produce a single combined action node
      actions = Graph.list_nodes(node_type: :action)
      assert length(actions) == 1
      assert hd(actions).title =~ "file_write"
      assert hd(actions).metadata["tool_name"] == "file_write"
    end
  end

  describe "fast tool collapse" do
    test "fast tool produces single combined action node", %{
      team_id: team_id,
      logger_pid: pid
    } do
      send_tool_executing(pid, "bob", "file_edit", team_id)
      # No sleep — completes immediately (< 1s)
      send_tool_complete(pid, "bob", "file_edit", team_id)
      Process.sleep(200)

      actions = Graph.list_nodes(node_type: :action)
      assert length(actions) == 1
      action = hd(actions)
      assert action.title =~ "[done]"
      assert action.metadata["elapsed_ms"] != nil

      # No separate outcome node
      assert Graph.list_nodes(node_type: :outcome) == []
    end

    test "slow tool produces action + outcome with edge", %{
      team_id: team_id,
      logger_pid: pid
    } do
      send_tool_executing(pid, "carol", "team_spawn", team_id)
      # Simulate slow tool by waiting over the threshold
      Process.sleep(1100)
      send_tool_complete(pid, "carol", "team_spawn", team_id)
      Process.sleep(200)

      actions = Graph.list_nodes(node_type: :action)
      assert length(actions) == 1
      action = hd(actions)
      assert action.title == "Tool: team_spawn (carol)"

      outcomes = Graph.list_nodes(node_type: :outcome)
      assert length(outcomes) == 1
      outcome = hd(outcomes)
      assert outcome.title == "Tool done: team_spawn (carol)"

      edges = Graph.list_edges(edge_type: :leads_to, to_node_id: outcome.id)
      assert Enum.any?(edges, &(&1.from_node_id == action.id))
    end
  end

  # --- Helpers ---

  defp send_tool_executing(pid, agent_name, tool_name, team_id) do
    sig =
      Loomkin.Signals.Agent.ToolExecuting.new!(
        %{agent_name: agent_name, team_id: team_id},
        subject: "payload"
      )
      |> Map.put(
        :data,
        %{
          agent_name: agent_name,
          team_id: team_id,
          payload: %{tool_name: tool_name}
        }
      )

    send(pid, {:signal, sig})
  end

  defp send_tool_complete(pid, agent_name, tool_name, team_id) do
    sig =
      Loomkin.Signals.Agent.ToolComplete.new!(
        %{agent_name: agent_name, team_id: team_id},
        subject: "payload"
      )
      |> Map.put(
        :data,
        %{
          agent_name: agent_name,
          team_id: team_id,
          payload: %{tool_name: tool_name}
        }
      )

    send(pid, {:signal, sig})
  end

  defp create_task(team_id, title) do
    %Loomkin.Schemas.TeamTask{}
    |> Loomkin.Schemas.TeamTask.changeset(%{team_id: team_id, title: title, status: :pending})
    |> Repo.insert()
  end
end
