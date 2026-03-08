defmodule LoomkinWeb.Live.AgentCardComponentTest do
  use LoomkinWeb.ConnCase, async: true
  @moduletag :pending

  describe "status controls" do
    test "renders pause button for :working status" do
      flunk("not yet implemented")
    end

    test "renders force-pause button for :waiting_permission status" do
      flunk("not yet implemented")
    end

    test "renders steer button (not resume) for :paused status" do
      flunk("not yet implemented")
    end
  end

  describe "dual state indicator" do
    test "renders pause_queued badge when pause_queued is true" do
      flunk("not yet implemented")
    end
  end

  describe "approval_pending" do
    test "renders approval_pending status dot correctly" do
      flunk("not yet implemented")
    end
  end

  describe "last-transition hint" do
    test "renders previous_status hint" do
      flunk("not yet implemented")
    end
  end
end
