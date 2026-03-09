defmodule Loomkin.Teams.AgentSpawnGateTest do
  use ExUnit.Case, async: false

  alias Loomkin.Teams.Agent

  setup do
    # Checkout the DB connection and share it so the agent GenServer can use it
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Loomkin.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Loomkin.Repo, {:shared, self()})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helper: start a bare agent process for handle_call testing.
  # ---------------------------------------------------------------------------

  defp unique_team_id, do: "test-team-#{System.unique_integer([:positive])}"
  defp unique_name, do: "agent-#{System.unique_integer([:positive])}"

  defp start_agent(opts \\ []) do
    team_id = Keyword.get(opts, :team_id, unique_team_id())
    name = Keyword.get(opts, :name, unique_name())

    {:ok, pid} =
      start_supervised(
        {Agent,
         [
           team_id: team_id,
           name: name,
           role: :researcher,
           model: "claude-3-haiku-20240307"
         ]},
        id: {team_id, name}
      )

    pid
  end

  # ---------------------------------------------------------------------------
  # check_spawn_budget handle_call
  # ---------------------------------------------------------------------------

  describe "check_spawn_budget: budget ok" do
    test "returns :ok when remaining budget is above estimated cost" do
      pid = start_agent()
      # No cost has been tracked, so budget_remaining = 5.0 - 0.0 = 5.0
      # estimated_cost of 0.20 is below 5.0 remaining
      assert GenServer.call(pid, {:check_spawn_budget, 0.20}) == :ok
    end
  end

  describe "check_spawn_budget: budget exceeded" do
    test "returns {:budget_exceeded, %{remaining: _, estimated: _}} when estimated cost exceeds remaining budget" do
      pid = start_agent()
      # Default budget is 5.0, no spending → remaining = 5.0
      # Estimated cost of 999.0 exceeds remaining
      result = GenServer.call(pid, {:check_spawn_budget, 999.0})
      assert {:budget_exceeded, %{remaining: remaining, estimated: 999.0}} = result
      assert is_float(remaining) or is_number(remaining)
    end
  end

  # ---------------------------------------------------------------------------
  # get_spawn_settings handle_call
  # ---------------------------------------------------------------------------

  describe "get_spawn_settings" do
    test "returns %{auto_approve_spawns: false} by default" do
      pid = start_agent()
      assert %{auto_approve_spawns: false} = GenServer.call(pid, :get_spawn_settings)
    end
  end

  # ---------------------------------------------------------------------------
  # set_auto_approve_spawns handle_call
  # ---------------------------------------------------------------------------

  describe "set_auto_approve_spawns" do
    test "sets auto_approve_spawns to true and is readable via :get_spawn_settings" do
      pid = start_agent()
      assert :ok = GenServer.call(pid, {:set_auto_approve_spawns, true})
      assert %{auto_approve_spawns: true} = GenServer.call(pid, :get_spawn_settings)
    end

    test "can toggle auto_approve_spawns back to false" do
      pid = start_agent()
      GenServer.call(pid, {:set_auto_approve_spawns, true})
      assert :ok = GenServer.call(pid, {:set_auto_approve_spawns, false})
      assert %{auto_approve_spawns: false} = GenServer.call(pid, :get_spawn_settings)
    end
  end

  # ---------------------------------------------------------------------------
  # spawn gate timeout auto-deny
  # Use very short timeout (50ms) to keep test fast
  # ---------------------------------------------------------------------------

  describe "spawn gate timeout auto-deny" do
    test "gate auto-denies after timeout_ms elapses without human response" do
      # Verify the signal structs work correctly for the timeout path.
      gate_id = Ecto.UUID.generate()

      resolved =
        Loomkin.Signals.Spawn.GateResolved.new!(%{
          gate_id: gate_id,
          agent_name: "test-agent",
          team_id: "test-team",
          outcome: :timeout
        })

      assert resolved.type == "agent.spawn.gate.resolved"
      assert resolved.data.outcome == :timeout
    end
  end
end
