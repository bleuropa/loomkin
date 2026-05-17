defmodule LoomkinWeb.OrchestrationIndexLive do
  @moduledoc """
  Multi-epic orchestration command center.

  Layout:
    * **Active epics** stream — in-flight epics (pending / in_progress /
      awaiting_human). Each row renders the persona, 9-dot phase bar, cost,
      ETA, a selection checkbox, and Pause / Cancel / Open actions. Bulk
      actions act on the selection.
    * **Recent epics** — closed / failed / cancelled epics from the last
      30 days (limit 50, newest first).
    * **Start a new epic** — the existing create form, moved to the bottom.

  Per-row updates flow through `Phoenix.LiveView` streams. We subscribe to
  the `orchestration.epic` PubSub topic on mount; each event triggers a
  single `stream_insert/3` (or `stream_delete/3` when the epic graduates
  out of the active set) instead of a full re-query.

  Styling reuses only existing Cozy Studio tokens (`card`, `badge`,
  `loom-btn`, `loom-btn-ghost`, `loom-btn-solid`).
  """
  use LoomkinWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import LoomkinWeb.TimeHelpers, only: [relative_time: 1]

  alias Loomkin.Orchestration
  alias Loomkin.Orchestration.Context
  alias Loomkin.Orchestration.Metrics
  alias Loomkin.Orchestration.Personas
  alias Loomkin.Orchestration.Schema.Epic
  alias Loomkin.Orchestration.SwarmCoordinator
  alias Loomkin.Repo
  alias LoomkinWeb.OrchestrationPanelComponent

  @topic "orchestration.epic"
  @active_statuses [:in_progress, :awaiting_human, :pending]
  @recent_statuses [:closed, :failed, :cancelled]
  @recent_window_days 30
  @recent_limit 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Loomkin.PubSub, @topic)

    active = list_active_epics()
    rows = Enum.map(active, &decorate_row/1)

    socket =
      socket
      |> assign(:page_title, "Orchestration")
      |> assign(:phase_list, Orchestration.phases())
      |> assign(:create_error, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:active_count, length(active))
      |> assign(:recent_epics, list_recent_epics())
      |> stream(:active_epics, rows)

    {:ok, socket}
  end

  ## ---------------------------------------------------------------- Streams

  defp list_active_epics do
    Repo.all(
      from(e in Epic,
        where: e.status in ^@active_statuses,
        order_by: [asc: e.inserted_at]
      )
    )
  end

  defp list_recent_epics do
    cutoff = DateTime.utc_now() |> DateTime.add(-@recent_window_days, :day)

    Repo.all(
      from(e in Epic,
        where: e.status in ^@recent_statuses and e.inserted_at >= ^cutoff,
        order_by: [desc: e.inserted_at],
        limit: ^@recent_limit
      )
    )
  end

  defp decorate_row(%Epic{} = epic) do
    %{
      id: epic.id,
      epic: epic,
      persona: persona_for(epic),
      cost_usd: safe_cost(epic),
      eta_ms: safe_eta(epic),
      phase_index: phase_index(epic.current_phase, Orchestration.phases())
    }
  end

  defp persona_for(%Epic{current_phase: nil}), do: Personas.for_phase(:pending)

  defp persona_for(%Epic{current_phase: phase}) when is_binary(phase) do
    Personas.for_phase(safe_atom(phase))
  end

  defp persona_for(%Epic{current_phase: phase}) when is_atom(phase) do
    Personas.for_phase(phase)
  end

  defp safe_atom(phase) when is_binary(phase) do
    String.to_existing_atom(phase)
  rescue
    _ -> :pending
  end

  defp safe_cost(%Epic{id: id}) when is_binary(id) do
    Metrics.cost_for_epic(id)
  rescue
    _ -> nil
  end

  defp safe_cost(_), do: nil

  defp safe_eta(%Epic{id: id, current_phase: phase}) when is_binary(id) do
    Metrics.eta_for_epic(id, phase)
  rescue
    _ -> nil
  end

  defp safe_eta(_), do: nil

  ## ----------------------------------------------------------------- PubSub

  @impl true
  def handle_info({@topic, %{epic_id: id}}, socket) when is_binary(id) do
    {:noreply, refresh_epic(socket, id)}
  end

  def handle_info({@topic, _other}, socket), do: {:noreply, socket}

  defp refresh_epic(socket, id) do
    case Context.get_epic(id) do
      nil ->
        socket
        |> Phoenix.LiveView.stream_delete_by_dom_id(
          :active_epics,
          "active_epics-" <> id
        )
        |> assign(:recent_epics, list_recent_epics())
        |> deselect(id)
        |> refresh_active_count()

      %Epic{status: status} = epic when status in @active_statuses ->
        row = decorate_row(epic)

        socket
        |> stream_insert(:active_epics, row)
        |> refresh_active_count()

      %Epic{status: status} = _epic when status in @recent_statuses ->
        socket
        |> Phoenix.LiveView.stream_delete_by_dom_id(
          :active_epics,
          "active_epics-" <> id
        )
        |> assign(:recent_epics, list_recent_epics())
        |> deselect(id)
        |> refresh_active_count()

      _ ->
        socket
    end
  end

  # One indexed `COUNT(*)` to keep the badge honest. Cheap and authoritative.
  defp refresh_active_count(socket) do
    n = Repo.aggregate(from(e in Epic, where: e.status in ^@active_statuses), :count, :id)
    assign(socket, :active_count, n)
  end

  defp deselect(socket, id) do
    assign(socket, :selected_ids, MapSet.delete(socket.assigns.selected_ids, id))
  end

  ## --------------------------------------------------------- Event handlers

  @impl true
  def handle_event("pause", %{"id" => epic_id}, socket) do
    SwarmCoordinator.pause(epic_id)
    {:noreply, socket}
  end

  def handle_event("cancel", %{"id" => epic_id}, socket) do
    SwarmCoordinator.cancel(epic_id)
    {:noreply, socket}
  end

  def handle_event("resume", %{"id" => epic_id}, socket) do
    SwarmCoordinator.resume(epic_id)
    {:noreply, socket}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  # phx-change on the bulk-select form. Phoenix sends back the array of
  # checked values, which we normalise into a MapSet. We accept either an
  # empty list (nothing checked) or a list of binary ids.
  def handle_event("select_changed", params, socket) do
    ids =
      case Map.get(params, "selected_ids") do
        nil -> []
        list when is_list(list) -> list
        _ -> []
      end

    {:noreply, assign(socket, :selected_ids, MapSet.new(ids))}
  end

  def handle_event("bulk_pause", _params, socket) do
    for id <- socket.assigns.selected_ids, do: SwarmCoordinator.pause(id)
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("bulk_cancel", _params, socket) do
    for id <- socket.assigns.selected_ids, do: SwarmCoordinator.cancel(id)
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("create_epic", %{"epic" => params}, socket) do
    case Context.create_epic(%{
           title: params["title"],
           spec: params["spec"] || "",
           priority: 2
         }) do
      {:ok, epic} ->
        epic_map = %{id: epic.id, title: epic.title, spec: epic.spec}
        callbacks = Loomkin.Orchestration.Callbacks.default_issue_callbacks()
        {:ok, _pid} = SwarmCoordinator.submit(epic_map, callbacks: callbacks)

        row = decorate_row(epic)

        {:noreply,
         socket
         |> put_flash(:info, "Orchestrating epic #{epic.title}")
         |> assign(:create_error, nil)
         |> stream_insert(:active_epics, row, at: 0)
         |> refresh_active_count()}

      {:error, changeset} ->
        {:noreply, assign(socket, :create_error, summarize_errors(changeset))}
    end
  end

  defp summarize_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map_join("; ", fn {k, {msg, _}} -> "#{k} #{msg}" end)
  end

  ## ------------------------------------------------------------- View utils

  defp phase_index(nil, _list), do: -1

  defp phase_index(phase, list) when is_atom(phase),
    do: Enum.find_index(list, &(&1 == phase)) || -1

  defp phase_index(phase, list) when is_binary(phase),
    do: Enum.find_index(list, &(Atom.to_string(&1) == phase)) || -1

  defp phase_label(nil), do: "—"
  defp phase_label(p) when is_atom(p), do: Atom.to_string(p)
  defp phase_label(p) when is_binary(p), do: p

  defp status_badge(:closed), do: {"badge badge-success", "closed"}
  defp status_badge(:failed), do: {"badge badge-danger", "failed"}
  defp status_badge(:cancelled), do: {"badge", "cancelled"}
  defp status_badge(:awaiting_human), do: {"badge badge-warning", "awaiting human"}
  defp status_badge(:in_progress), do: {"badge", "in progress"}
  defp status_badge(:pending), do: {"badge", "pending"}
  defp status_badge(other), do: {"badge", to_string(other)}

  # Glyph used in the "Recent" list (visually mirrors the CLI tail).
  defp recent_glyph(:closed), do: "✓"
  defp recent_glyph(:failed), do: "✗"
  defp recent_glyph(:cancelled), do: "○"
  defp recent_glyph(_), do: "•"

  defp paused?(%{metadata: %{} = meta}) do
    Map.get(meta, "paused") == true or Map.get(meta, :paused) == true
  end

  defp paused?(_), do: false

  defp selected?(selected_ids, id), do: MapSet.member?(selected_ids, id)

  ## --------------------------------------------------------------- Template

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="min-h-screen px-6 py-10"
      style="background: var(--surface-0); color: var(--text-primary);"
      aria-labelledby="orch-index-h"
    >
      <header class="max-w-5xl mx-auto mb-8">
        <p class="text-xs font-mono mb-2" style="color: var(--text-muted);">
          <.link navigate={~p"/"} class="hover:underline">← home</.link>
          <span class="mx-1">·</span>
          <.link navigate={~p"/orchestration/knowledge"} class="hover:underline">knowledge</.link>
          <span class="mx-1">·</span>
          <.link navigate={~p"/orchestration/metrics"} class="hover:underline">metrics</.link>
        </p>
        <h1 id="orch-index-h" class="text-2xl font-semibold" style="color: var(--text-primary);">
          Orchestration
        </h1>
        <p class="text-sm mt-1" style="color: var(--text-secondary);">
          command center · multi-epic steering · live phase progression
        </p>
      </header>

      <%!-- ────────────────────────────────────────────────────────────────
            Active epics — top of the page, stream-driven for per-row updates
      ──────────────────────────────────────────────────────────────── --%>
      <section
        class="max-w-5xl mx-auto mb-10"
        aria-labelledby="orch-active-h"
        data-testid="orchestration-active-section"
      >
        <h2
          id="orch-active-h"
          class="text-lg font-medium mb-4 flex items-baseline justify-between gap-2"
          style="color: var(--text-primary);"
        >
          <span>Active epics</span>
          <span
            class="text-xs font-mono"
            style="color: var(--text-muted);"
            data-testid="orchestration-active-count"
          >
            {@active_count} in flight
          </span>
        </h2>

        <p
          :if={@active_count == 0}
          class="card p-6 text-sm"
          style="color: var(--text-muted);"
          data-testid="orchestration-active-empty"
        >
          No active epics — start one below.
        </p>

        <form
          :if={@active_count > 0}
          phx-change="select_changed"
          aria-label="Bulk-select active epics"
        >
          <ul
            id="active-epics-stream"
            phx-update="stream"
            role="list"
            class="flex flex-col gap-3"
          >
            <li
              :for={{dom_id, row} <- @streams.active_epics}
              id={dom_id}
              class="card hover-lift p-4"
              data-testid="orchestration-active-row"
              data-epic-id={row.id}
            >
              <div class="flex items-start gap-3">
                <input
                  type="checkbox"
                  name="selected_ids[]"
                  value={row.id}
                  checked={selected?(@selected_ids, row.id)}
                  aria-labelledby={"epic-#{row.id}-title"}
                  class="mt-1.5 cursor-pointer"
                />

                <div class="flex-1 min-w-0">
                  <div class="flex items-baseline justify-between gap-3">
                    <h3
                      id={"epic-#{row.id}-title"}
                      class="font-medium flex items-center gap-2 min-w-0"
                      style="color: var(--text-primary);"
                    >
                      <span aria-hidden="true">{row.persona.icon}</span>
                      <span class="text-xs uppercase tracking-wider" style="color: var(--text-muted);">
                        {row.persona.name}
                      </span>
                      <span style="color: var(--text-muted);">·</span>
                      <span class="truncate">{row.epic.title}</span>
                    </h3>

                    <span class="flex items-center gap-2 shrink-0">
                      <% {cls, lbl} = status_badge(row.epic.status) %>
                      <span class={cls}>{lbl}</span>
                      <span :if={paused?(row.epic)} class="badge badge-warning">
                        paused
                      </span>
                    </span>
                  </div>

                  <ol
                    class="mt-3 flex gap-1.5"
                    role="img"
                    aria-label={"phase " <> phase_label(row.epic.current_phase)}
                  >
                    <li
                      :for={{ph, i} <- Enum.with_index(@phase_list)}
                      title={Atom.to_string(ph)}
                      class="block h-2 w-2 rounded-full"
                      style={
                        if i <= row.phase_index do
                          "background: var(--brand);"
                        else
                          "background: var(--surface-3);"
                        end
                      }
                      aria-hidden="true"
                    >
                    </li>
                    <li class="ml-2 text-xs font-mono" style="color: var(--text-muted);">
                      phase: {phase_label(row.epic.current_phase)}
                    </li>
                  </ol>

                  <dl
                    class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs font-mono"
                    style="color: var(--text-muted);"
                  >
                    <div class="flex gap-1" data-testid={"epic-#{row.id}-cost"}>
                      <dt>cost:</dt>
                      <dd style="color: var(--text-primary);">
                        {OrchestrationPanelComponent.format_cost(row.cost_usd)}
                      </dd>
                    </div>
                    <div class="flex gap-1" data-testid={"epic-#{row.id}-eta"}>
                      <dt>eta:</dt>
                      <dd style="color: var(--text-primary);">
                        {OrchestrationPanelComponent.format_eta(row.eta_ms)}
                      </dd>
                    </div>
                  </dl>

                  <div
                    class="mt-3 flex flex-wrap gap-2"
                    data-testid={"orchestration-index-actions-" <> row.id}
                  >
                    <button
                      :if={not paused?(row.epic)}
                      type="button"
                      class="loom-btn loom-btn-ghost"
                      phx-click="pause"
                      phx-value-id={row.id}
                      aria-label={"Pause " <> row.epic.title}
                    >
                      Pause
                    </button>
                    <button
                      :if={paused?(row.epic)}
                      type="button"
                      class="loom-btn loom-btn-solid"
                      phx-click="resume"
                      phx-value-id={row.id}
                      aria-label={"Resume " <> row.epic.title}
                    >
                      Resume
                    </button>
                    <button
                      type="button"
                      class="loom-btn loom-btn-ghost"
                      phx-click="cancel"
                      phx-value-id={row.id}
                      aria-label={"Cancel " <> row.epic.title}
                    >
                      Cancel
                    </button>
                    <.link
                      navigate={~p"/orchestration/#{row.id}"}
                      class="loom-btn loom-btn-ghost"
                      aria-label={"Open " <> row.epic.title}
                    >
                      Open
                    </.link>
                  </div>
                </div>
              </div>
            </li>
          </ul>

          <div
            :if={MapSet.size(@selected_ids) > 0}
            class="card mt-4 p-3 flex flex-wrap items-center gap-3"
            role="region"
            aria-label="Bulk actions"
            data-testid="orchestration-bulk-toolbar"
          >
            <span class="text-xs font-mono" style="color: var(--text-muted);">
              {MapSet.size(@selected_ids)} selected
            </span>
            <button
              type="button"
              class="loom-btn loom-btn-ghost"
              phx-click="bulk_pause"
              aria-label="Pause selected epics"
            >
              Pause selected
            </button>
            <button
              type="button"
              class="loom-btn loom-btn-ghost"
              phx-click="bulk_cancel"
              aria-label="Cancel selected epics"
            >
              Cancel selected
            </button>
            <button
              type="button"
              class="loom-btn loom-btn-ghost ml-auto"
              phx-click="clear_selection"
              aria-label="Clear selection"
            >
              Clear
            </button>
          </div>
        </form>
      </section>

      <%!-- ────────────────────────────────────────────────────────────────
            Recent epics — closed / failed / cancelled (last 30d, max 50)
      ──────────────────────────────────────────────────────────────── --%>
      <section
        class="max-w-5xl mx-auto mb-10"
        aria-labelledby="orch-recent-h"
        data-testid="orchestration-recent-section"
      >
        <h2
          id="orch-recent-h"
          class="text-lg font-medium mb-4"
          style="color: var(--text-primary);"
        >
          Recent
          <span class="text-xs font-mono" style="color: var(--text-muted);">(last 30 days)</span>
        </h2>

        <p
          :if={@recent_epics == []}
          class="card p-6 text-sm"
          style="color: var(--text-muted);"
          data-testid="orchestration-recent-empty"
        >
          No recent epics.
        </p>

        <ul :if={@recent_epics != []} role="list" class="flex flex-col gap-2">
          <li
            :for={epic <- @recent_epics}
            class="card hover-lift p-3"
            data-testid="orchestration-recent-row"
          >
            <.link
              navigate={~p"/orchestration/#{epic.id}"}
              class="flex items-baseline justify-between gap-3 no-underline"
              style="color: inherit;"
            >
              <span class="flex items-baseline gap-2 min-w-0">
                <span
                  class="text-sm font-mono"
                  style="color: var(--text-muted);"
                  aria-hidden="true"
                >
                  {recent_glyph(epic.status)}
                </span>
                <strong class="font-medium truncate" style="color: var(--text-primary);">
                  {epic.title}
                </strong>
              </span>
              <span class="flex items-center gap-2 shrink-0">
                <% {cls, lbl} = status_badge(epic.status) %>
                <span class={cls}>{lbl}</span>
                <span class="text-xs font-mono" style="color: var(--text-muted);">
                  {relative_time(epic.inserted_at)}
                </span>
              </span>
            </.link>
          </li>
        </ul>
      </section>

      <%!-- ────────────────────────────────────────────────────────────────
            Start a new epic — now at the bottom of the command center
      ──────────────────────────────────────────────────────────────── --%>
      <section
        class="card max-w-5xl mx-auto p-6"
        aria-labelledby="orch-new-h"
        data-testid="orchestration-new-epic-form"
      >
        <h2 id="orch-new-h" class="text-lg font-medium mb-4" style="color: var(--text-primary);">
          Start a new epic
        </h2>
        <form phx-submit="create_epic" class="flex flex-col gap-4">
          <label class="flex flex-col gap-1 text-sm" style="color: var(--text-secondary);">
            <span>Title</span>
            <input
              name="epic[title]"
              type="text"
              required
              maxlength="120"
              class="rounded px-3 py-2 text-sm focus:outline-none focus:ring-2"
              style="background: var(--surface-1); border: 1px solid var(--border-default); color: var(--text-primary);"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm" style="color: var(--text-secondary);">
            <span>Spec</span>
            <textarea
              name="epic[spec]"
              rows="4"
              required
              class="rounded px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2"
              style="background: var(--surface-1); border: 1px solid var(--border-default); color: var(--text-primary);"
            ></textarea>
          </label>
          <button type="submit" class="loom-btn loom-btn-solid self-start">
            Orchestrate
          </button>
        </form>
        <p :if={@create_error} role="alert" class="mt-3 text-sm" style="color: var(--accent-rose);">
          {@create_error}
        </p>
      </section>
    </main>
    """
  end
end
