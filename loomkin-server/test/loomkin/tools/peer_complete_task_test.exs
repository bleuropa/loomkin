defmodule Loomkin.Tools.PeerCompleteTaskTest do
  use Loomkin.DataCase, async: false

  alias Loomkin.Teams.{Manager, Tasks}
  alias Loomkin.Tools.PeerCompleteTask

  setup do
    {:ok, team_id} = Manager.create_team(name: "peer-complete-task-test")
    Loomkin.Signals.subscribe("context.offloaded")

    on_exit(fn ->
      DynamicSupervisor.which_children(Loomkin.Teams.AgentSupervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(Loomkin.Teams.AgentSupervisor, pid)
      end)

      Loomkin.Teams.TableRegistry.delete_table(team_id)
    end)

    %{team_id: team_id}
  end

  describe "verify_files_changed/2" do
    test "returns empty list when no files claimed" do
      assert PeerCompleteTask.verify_files_changed([], "/tmp") == []
    end

    test "returns empty list when project_path is nil" do
      assert PeerCompleteTask.verify_files_changed(["some/file.ex"], nil) == []
    end

    test "returns empty list when all claimed files exist" do
      # Create a temporary file to verify against
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "peer_complete_task_test_#{:rand.uniform(100_000)}.txt")
      File.write!(test_file, "test content")

      try do
        relative_path = Path.relative_to(test_file, tmp_dir)
        assert PeerCompleteTask.verify_files_changed([relative_path], tmp_dir) == []
      after
        File.rm(test_file)
      end
    end

    test "returns warnings for files that don't exist" do
      tmp_dir = System.tmp_dir!()
      fake_file = "definitely_not_a_real_file_#{:rand.uniform(100_000)}.ex"

      warnings = PeerCompleteTask.verify_files_changed([fake_file], tmp_dir)

      assert length(warnings) == 1
      assert hd(warnings) =~ fake_file
      assert hd(warnings) =~ "not found on disk"
    end

    test "handles mix of existing and non-existing files" do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "peer_complete_real_#{:rand.uniform(100_000)}.txt")
      File.write!(test_file, "test content")

      try do
        relative_path = Path.relative_to(test_file, tmp_dir)
        fake_file = "no_such_file_#{:rand.uniform(100_000)}.ex"

        warnings =
          PeerCompleteTask.verify_files_changed([relative_path, fake_file], tmp_dir)

        assert length(warnings) == 1
        assert hd(warnings) =~ fake_file
      after
        File.rm(test_file)
      end
    end

    test "filters out empty strings and nils" do
      tmp_dir = System.tmp_dir!()
      assert PeerCompleteTask.verify_files_changed(["", nil], tmp_dir) == []
    end
  end

  describe "run/2 researcher publication" do
    test "auto-offloads researcher findings before task completion", %{team_id: team_id} do
      {:ok, task} = Tasks.create_task(team_id, %{title: "Audit vault indexing"})

      params = %{
        team_id: team_id,
        task_id: task.id,
        result: "Reviewed the vault indexing path and identified the current ingestion gaps.",
        actions_taken: [
          "Read vault ingestion modules",
          "Compared current flow to desired repo indexing flow"
        ],
        discoveries: ["Vault currently lacks a code-repo ingestion entry point"],
        open_questions: ["Should repo ingestion create one keeper per file or per subsystem?"]
      }

      context = %{
        team_id: team_id,
        agent_name: "researcher-1",
        role: :researcher,
        publication_state: %{offloaded: false}
      }

      task_id = task.id

      assert {:ok, %{result: result, task_id: ^task_id}} =
               PeerCompleteTask.run(params, context)

      assert result =~ "Findings published: research: Audit vault indexing"
      assert length(Manager.list_keepers(team_id)) == 1

      assert_receive {:signal,
                      %Jido.Signal{
                        type: "context.offloaded",
                        data: %{
                          agent_name: "researcher-1",
                          team_id: ^team_id,
                          payload: %{
                            topic: "research: Audit vault indexing",
                            source: "peer_complete_task"
                          }
                        }
                      }}
    end

    test "does not auto-offload when findings were already offloaded in this loop", %{
      team_id: team_id
    } do
      {:ok, task} = Tasks.create_task(team_id, %{title: "Summarize current cli layout"})

      params = %{
        team_id: team_id,
        task_id: task.id,
        result: "Summarized the current layout issues around crowded panes and command input.",
        actions_taken: ["Read the cli layout components"],
        discoveries: ["Status and prompt areas are competing for the same vertical space"]
      }

      context = %{
        team_id: team_id,
        agent_name: "researcher-1",
        role: :researcher,
        publication_state: %{offloaded: true}
      }

      assert {:ok, %{result: result}} = PeerCompleteTask.run(params, context)
      refute result =~ "Findings published:"
      assert Manager.list_keepers(team_id) == []
      refute_receive {:signal, %Jido.Signal{type: "context.offloaded"}}, 200
    end
  end
end
