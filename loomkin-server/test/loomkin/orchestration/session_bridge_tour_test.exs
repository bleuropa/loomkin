defmodule Loomkin.Orchestration.SessionBridgeTourTest do
  @moduledoc """
  First-time orchestration tour broadcast.

  Verifies that `Loomkin.Orchestration.SessionBridge.dispatch/3` emits the
  `session.orchestration.tour_needed` signal once per user (the first time
  they trigger a `:complex_task`), and never again afterwards.
  """

  use Loomkin.DataCase, async: false

  alias Loomkin.Accounts
  alias Loomkin.Orchestration.SessionBridge
  alias Loomkin.Orchestration.LLM.Stub
  alias Loomkin.Session.Persistence
  alias Loomkin.Signals

  import Loomkin.AccountsFixtures

  setup do
    start_supervised!(Stub)
    prev = Application.get_env(:loomkin, Loomkin.Orchestration, [])

    Application.put_env(
      :loomkin,
      Loomkin.Orchestration,
      Keyword.put(prev, :llm_adapter, Stub)
    )

    for pid <-
          [
            Process.whereis(Loomkin.Orchestration.KnowledgeStore),
            Process.whereis(Loomkin.Orchestration.SwarmCoordinator),
            Process.whereis(Loomkin.Orchestration.Curator)
          ],
        is_pid(pid) do
      Ecto.Adapters.SQL.Sandbox.allow(Loomkin.Repo, self(), pid)
    end

    sub = Signals.subscribe("session.orchestration.tour_needed")

    on_exit(fn ->
      Signals.unsubscribe(sub)
      Application.put_env(:loomkin, Loomkin.Orchestration, prev)
    end)

    user = user_fixture()

    {:ok, session} =
      Persistence.create_session(%{
        model: "anthropic:claude-sonnet-4-5",
        project_path: "/tmp",
        user_id: user.id
      })

    {:ok, user: user, session: session, sub: sub}
  end

  test "broadcasts tour_needed on first :complex_task for an unseen user", %{
    user: user,
    session: session
  } do
    refute user.has_seen_orchestration_tour

    session_state = %{id: session.id, team_id: nil, workspace_id: nil, user_id: user.id}
    message = "refactor lib/loomkin/session/session.ex to use gen_statem"

    assert {:complex_task, _epic_id} = SessionBridge.dispatch(session_state, message)

    expected_user_id = user.id

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "session.orchestration.tour_needed",
                      data: %{user_id: ^expected_user_id, phases: phases, personas: personas}
                    }},
                   1_000

    assert is_list(phases)
    assert length(phases) == 9
    assert Enum.any?(phases, fn p -> p[:name] == "Planner" end)
    assert is_list(personas)
    assert Enum.any?(personas, fn p -> p[:name] == "Coder" end)
  end

  test "does NOT broadcast tour_needed once the user has seen the tour", %{
    user: user,
    session: session
  } do
    {:ok, user} = Accounts.mark_orchestration_tour_seen(user)
    assert user.has_seen_orchestration_tour

    session_state = %{id: session.id, team_id: nil, workspace_id: nil, user_id: user.id}
    message = "implement a new feature flag in lib/loomkin/feature_flags.ex"

    assert {:complex_task, _epic_id} = SessionBridge.dispatch(session_state, message)

    refute_receive {:signal, %Jido.Signal{type: "session.orchestration.tour_needed"}}, 300
  end

  test "does not broadcast for :fast_chat / :tool_use intents", %{
    user: user,
    session: session
  } do
    session_state = %{id: session.id, team_id: nil, workspace_id: nil, user_id: user.id}

    # A plain greeting is :fast_chat / :tool_use, never :complex_task.
    _ = SessionBridge.dispatch(session_state, "hi")

    refute_receive {:signal, %Jido.Signal{type: "session.orchestration.tour_needed"}}, 200
  end
end
