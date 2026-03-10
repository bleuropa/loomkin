defmodule LoomkinWeb.ConnCase do
  @moduledoc """
  Test case for controllers and LiveView tests that require a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint LoomkinWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      use Phoenix.VerifiedRoutes,
        endpoint: LoomkinWeb.Endpoint,
        router: LoomkinWeb.Router,
        statics: LoomkinWeb.static_paths()
    end
  end

  setup tags do
    # Ensure the session ETS table exists (needed for :ets session store)
    if :ets.whereis(:loomkin_sessions) == :undefined do
      :ets.new(:loomkin_sessions, [:named_table, :public, :set])
    end

    # Start the endpoint if not already running.
    # Use try/rescue to handle the race where another async test module
    # starts the endpoint between our whereis check and start_supervised! call.
    unless Process.whereis(LoomkinWeb.Endpoint) do
      try do
        start_supervised!(LoomkinWeb.Endpoint)
      rescue
        RuntimeError -> :ok
      end
    end

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Loomkin.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
