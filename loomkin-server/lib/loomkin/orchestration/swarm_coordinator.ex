defmodule Loomkin.Orchestration.SwarmCoordinator do
  @moduledoc """
  Singleton GenServer that schedules epics across the orchestration runtime.

  Responsibilities (multi-epic orchestration):

    * Priority queueing — P0 > P1 > P2 > P3 > P4
    * Spawn `IssueOrchestrator` processes via `EpicSupervisor`
    * Health checks via DynamicSupervisor.which_children
    * Conflict awareness (a future hook — currently first-fit)

  The Coordinator exposes a small synchronous API; LiveView and the CLI both
  call into it.
  """
  use GenServer

  alias Loomkin.Orchestration.{EpicSupervisor, IssueOrchestrator}

  @name __MODULE__

  ## API

  def start_link(opts) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submit an epic. `opts` are forwarded to `IssueOrchestrator.start_link/1`
  alongside the epic itself.

  Returns `{:ok, pid}` on successful spawn.
  """
  @spec submit(map(), Keyword.t(), GenServer.name()) ::
          {:ok, pid()} | {:error, term()}
  def submit(epic, opts \\ [], server \\ @name) when is_map(epic) do
    GenServer.call(server, {:submit, epic, opts})
  end

  @doc "Returns the list of active epic orchestrators with metadata."
  def list_active(server \\ @name), do: GenServer.call(server, :list_active)

  @doc """
  Cast `:pause` to the orchestrator owning `epic_id`.

  Resolution: `Registry.lookup(EpicRegistry, epic_id)`.
  Returns `:ok` if the cast was delivered, `{:error, :not_found}` otherwise.
  """
  @spec pause(binary(), GenServer.name()) :: :ok | {:error, :not_found}
  def pause(epic_id, server \\ @name), do: send_to_orchestrator(epic_id, :pause, server)

  @doc "Cast `:cancel` to the orchestrator owning `epic_id`."
  @spec cancel(binary(), GenServer.name()) :: :ok | {:error, :not_found}
  def cancel(epic_id, server \\ @name), do: send_to_orchestrator(epic_id, :cancel, server)

  @doc """
  Cast `:resume_from_pause` to the orchestrator owning `epic_id`.

  Resumes a paused orchestrator back to whatever state it was in before the
  `:pause` cast.
  """
  @spec resume(binary(), GenServer.name()) :: :ok | {:error, :not_found}
  def resume(epic_id, server \\ @name),
    do: send_to_orchestrator(epic_id, :resume_from_pause, server)

  @doc "Cast `:approve` to clear an `:awaiting_approval` block."
  @spec approve(binary(), GenServer.name()) :: :ok | {:error, :not_found}
  def approve(epic_id, server \\ @name), do: send_to_orchestrator(epic_id, :approve, server)

  @doc "Cast `:reject` to cancel an `:awaiting_approval` block."
  @spec reject(binary(), GenServer.name()) :: :ok | {:error, :not_found}
  def reject(epic_id, server \\ @name), do: send_to_orchestrator(epic_id, :reject, server)

  defp send_to_orchestrator(epic_id, message, _server) when is_binary(epic_id) do
    case Registry.lookup(Loomkin.Orchestration.EpicRegistry, epic_id) do
      [{pid, _}] ->
        :gen_statem.cast(pid, message)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp send_to_orchestrator(_, _, _), do: {:error, :not_found}

  ## Callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:submit, epic, opts}, _from, state) do
    epic_id = Map.get(epic, :id) || Map.get(epic, "id") || Ecto.UUID.generate()
    epic = Map.put(epic, :id, epic_id)

    callbacks = Keyword.get(opts, :callbacks, %{})

    start_opts =
      Keyword.merge(opts,
        epic: epic,
        callbacks: callbacks,
        name: {:via, Registry, {Loomkin.Orchestration.EpicRegistry, epic_id}}
      )

    case EpicSupervisor.start_orchestrator(start_opts) do
      {:ok, pid} ->
        IssueOrchestrator.start(pid)
        {:reply, {:ok, pid}, Map.put(state, epic_id, pid)}

      {:error, {:already_started, pid}} ->
        {:reply, {:ok, pid}, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call(:list_active, _from, state) do
    children = EpicSupervisor.list_active()
    {:reply, children, state}
  end
end
