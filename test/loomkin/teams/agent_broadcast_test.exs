defmodule Loomkin.Teams.AgentBroadcastTest do
  use ExUnit.Case, async: true
  @moduletag :pending

  alias Loomkin.Teams.Agent

  describe "broadcast delivery" do
    test "sends message to all agents in a team" do
      flunk("not yet implemented")
    end

    test "broadcast to team with no agents does not crash" do
      flunk("not yet implemented")
    end

    test "message is prefixed with broadcast marker" do
      flunk("not yet implemented")
    end

    test "dead agent PID does not crash broadcast loop" do
      flunk("not yet implemented")
    end

    test "injects broadcast into paused agent's paused_state.messages" do
      flunk("not yet implemented")
    end
  end
end
