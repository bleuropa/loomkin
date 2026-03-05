defmodule LoomkinWeb.SessionSwitcherComponent do
  use LoomkinWeb, :live_component

  require Logger

  alias Loomkin.Session.Persistence

  def update(assigns, socket) do
    project_path = assigns[:project_path]
    show_all = socket.assigns[:show_all_projects] || false

    sessions =
      if show_all || is_nil(project_path) do
        list_all_sessions()
      else
        Persistence.list_sessions(project_path: project_path)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(sessions: sessions, dropdown_open: false, show_all_projects: show_all)}
  end

  def render(assigns) do
    ~H"""
    <div
      class="relative"
      id="session-switcher-wrapper"
      phx-click-away="close_dropdown"
      phx-target={@myself}
    >
      <%!-- Trigger button --%>
      <button
        phx-click="toggle_dropdown"
        phx-target={@myself}
        class="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs transition-all duration-200 press-down max-w-[180px]"
        style={"border: 1px solid " <> if(@dropdown_open, do: "var(--border-brand)", else: "var(--border-subtle)") <> "; color: var(--text-secondary);"}
      >
        <span style="color: var(--text-muted);">
          <.icon name="hero-clock-mini" class="w-3 h-3 flex-shrink-0" />
        </span>
        <span class="truncate">{current_session_label(@session_id, @sessions)}</span>
        <svg
          class={"w-3 h-3 flex-shrink-0 transition-transform duration-200 " <> if(@dropdown_open, do: "rotate-180", else: "")}
          style="color: var(--text-muted);"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      <%!-- Dropdown --%>
      <div
        :if={@dropdown_open}
        class="absolute right-0 top-full mt-1.5 w-60 card-elevated overflow-hidden animate-scale-in"
        style="z-index: 100;"
      >
        <%!-- New session option --%>
        <button
          phx-click="new_session"
          phx-target={@myself}
          class="w-full flex items-center gap-2 px-3 py-2 text-xs transition-colors interactive"
          style="color: var(--text-brand); border-bottom: 1px solid var(--border-subtle);"
        >
          <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
          <span class="font-medium">New Session</span>
        </button>

        <%!-- Session list --%>
        <div class="max-h-48 overflow-y-auto py-1">
          <button
            :for={session <- @sessions}
            phx-click="select_session"
            phx-value-id={session.id}
            phx-target={@myself}
            class="w-full flex items-center gap-2 px-3 py-1.5 text-xs transition-colors interactive"
            style={
              if session.id == @session_id,
                do: "background: rgba(124, 58, 237, 0.1); color: var(--text-brand);",
                else: "color: var(--text-secondary);"
            }
          >
            <span :if={session.id == @session_id} class="flex-shrink-0">
              <span style="color: var(--text-brand);">
                <.icon name="hero-check-mini" class="w-3 h-3" />
              </span>
            </span>
            <span :if={session.id != @session_id} class="w-3 flex-shrink-0" />
            <span class="truncate flex-1 text-left">{session_label(session)}</span>
            <span class="text-[10px] flex-shrink-0" style="color: var(--text-muted);">
              {relative_time(session)}
            </span>
          </button>
        </div>

        <div
          :if={@sessions == []}
          class="px-3 py-3 text-xs text-center"
          style="color: var(--text-muted);"
        >
          No previous sessions
        </div>

        <%!-- All projects toggle --%>
        <button
          phx-click="toggle_all_projects"
          phx-target={@myself}
          class="w-full flex items-center gap-2 px-3 py-1.5 text-[11px] transition-colors interactive"
          style="border-top: 1px solid var(--border-subtle); color: var(--text-muted);"
        >
          <span>{if @show_all_projects, do: "This project only", else: "All projects"}</span>
        </button>
      </div>
    </div>
    """
  end

  def handle_event("toggle_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: !socket.assigns.dropdown_open)}
  end

  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  def handle_event("new_session", _params, socket) do
    send(self(), :new_session)
    {:noreply, assign(socket, dropdown_open: false)}
  end

  def handle_event("select_session", %{"id" => session_id}, socket) do
    send(self(), {:select_session, session_id})
    {:noreply, assign(socket, dropdown_open: false)}
  end

  def handle_event("toggle_all_projects", _params, socket) do
    show_all = !socket.assigns.show_all_projects
    project_path = socket.assigns[:project_path]

    sessions =
      if show_all || is_nil(project_path) do
        list_all_sessions()
      else
        Persistence.list_sessions(project_path: project_path)
      end

    {:noreply, assign(socket, show_all_projects: show_all, sessions: sessions)}
  end

  defp list_all_sessions do
    Persistence.list_sessions()
  end

  defp current_session_label(session_id, sessions) do
    case Enum.find(sessions, &(&1.id == session_id)) do
      nil -> "Session #{String.slice(session_id, 0, 8)}"
      session -> session_label(session)
    end
  end

  defp session_label(session) do
    title = session.title || "Untitled"

    if String.length(title) > 24 do
      String.slice(title, 0, 24) <> "..."
    else
      title
    end
  end

  defp relative_time(session) do
    case Map.get(session, :updated_at) || Map.get(session, :inserted_at) do
      nil ->
        ""

      datetime ->
        diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

        cond do
          diff < 60 -> "now"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          true -> "#{div(diff, 86400)}d ago"
        end
    end
  rescue
    e ->
      Logger.warning("[SessionSwitcher] relative_time failed: #{Exception.message(e)}")
      "just now"
  end
end
