defmodule Loomkin.Teams.AgentStateMachineTest do
  use ExUnit.Case, async: true
  @moduletag :pending

  alias Loomkin.Teams.Agent

  describe "request_pause guards" do
    test "queues pause when status is :waiting_permission" do
      flunk("not yet implemented")
    end

    test "sets pause_requested when status is :working" do
      flunk("not yet implemented")
    end

    test "no-op when status is :idle" do
      flunk("not yet implemented")
    end

    test "queues pause when status is :approval_pending" do
      flunk("not yet implemented")
    end
  end

  describe "permission_response with pause_queued" do
    test "auto-transitions to :paused when pause_queued is true" do
      flunk("not yet implemented")
    end

    test "preserves denial context in paused_state when denied with pause_queued" do
      flunk("not yet implemented")
    end

    test "resumes work normally when pause_queued is false" do
      flunk("not yet implemented")
    end
  end

  describe "pause_queued field" do
    test "defaults to false in struct" do
      flunk("not yet implemented")
    end
  end

  describe "set_status_and_broadcast guards" do
    test "rejects direct transition from :waiting_permission to :paused" do
      flunk("not yet implemented")
    end
  end
end
