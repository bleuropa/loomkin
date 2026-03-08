defmodule LoomkinWeb.Live.WorkspaceStateMachineTest do
  use LoomkinWeb.ConnCase, async: false
  @moduletag :pending

  describe "force-pause" do
    test "force_pause_card_agent cancels pending permission and pauses agent" do
      flunk("not yet implemented")
    end

    test "force-pause only works when agent is in :waiting_permission" do
      flunk("not yet implemented")
    end
  end

  describe "steer-only resume" do
    test "resume redirects to steer flow" do
      flunk("not yet implemented")
    end
  end
end
