defmodule LoomkinWeb.AgentRosterComponent do
  @moduledoc """
  Left-panel sidebar for mission control mode.

  Displays agent roster with status indicators, task summary, and budget bar.
  Communicates focus/unpin actions to the parent LiveView via `send(self(), msg)`.
  """

  use LoomkinWeb, :live_component

  @agent_colors [
    "#818cf8",
    "#34d399",
    "#f472b6",
    "#fb923c",
    "#22d3ee",
    "#a78bfa",
    "#fbbf24",
    "#4ade80"
  ]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, tasks_collapsed: false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("focus_agent", %{"agent" => agent_name}, socket) do
    if socket.assigns[:focused_agent] == agent_name do
      send(self(), {:unpin_agent})
    else
      send(self(), {:focus_agent, agent_name})
    end

    {:noreply, socket}
  end

  def handle_event("toggle_tasks", _params, socket) do
    {:noreply, assign(socket, tasks_collapsed: !socket.assigns.tasks_collapsed)}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-56 w-full flex-col border-b border-gray-800 bg-gray-950 xl:h-full xl:w-56 xl:border-b-0 xl:border-r">
      <%!-- Team Header --%>
      <div class="px-3 py-3 border-b border-gray-800 flex items-center justify-between">
        <span class="text-sm font-semibold text-violet-400 truncate">{@team_id}</span>
        <span class="text-xs bg-gray-800 text-gray-400 px-1.5 py-0.5 rounded-full font-mono">
          {length(@agents)}
        </span>
      </div>

      <%!-- Agents Section --%>
      <div class="flex-1 overflow-y-auto">
        <div class="px-3 py-2">
          <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Agents</h3>
        </div>

        <div :if={@agents == []} class="px-3 py-4 text-center text-xs text-gray-600">
          No agents spawned
        </div>

        <div class="space-y-0.5 px-1.5">
          <button
            :for={agent <- @agents}
            phx-click="focus_agent"
            phx-value-agent={agent.name}
            phx-target={@myself}
            class={"w-full text-left px-2 py-2 rounded-md transition cursor-pointer hover:bg-gray-900 #{if @focused_agent == agent.name, do: "bg-gray-900 border border-violet-500/50", else: "border border-transparent"}"}
          >
            <%!-- Row 1: status dot + name + role badge --%>
            <div class="flex items-center gap-2">
              <span class={"w-2 h-2 rounded-full flex-shrink-0 #{status_dot_class(agent.status)}"}>
              </span>
              <span
                class="text-sm font-medium truncate flex-1"
                style={"color: #{agent_color(agent.name)}"}
              >
                {agent.name}
              </span>
              <span class="text-xs bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded font-medium">
                {format_role(agent.role)}
              </span>
            </div>
            <%!-- Row 2: current task --%>
            <div class="mt-0.5 pl-4">
              <span class={"text-xs #{status_text_color(agent.status)}"}>
                {Map.get(agent, :current_task) || status_label(agent.status)}
              </span>
            </div>
          </button>
        </div>
      </div>

      <%!-- Divider --%>
      <div class="border-t border-gray-800"></div>

      <%!-- Tasks Section (collapsible) --%>
      <div class="flex-shrink-0">
        <button
          phx-click="toggle_tasks"
          phx-target={@myself}
          class="w-full flex items-center justify-between px-3 py-2 hover:bg-gray-900/50 transition cursor-pointer"
        >
          <h3 class="text-xs font-semibold text-gray-500 uppercase tracking-wider">Tasks</h3>
          <span class={"text-xs text-gray-600 transition-transform #{if @tasks_collapsed, do: "-rotate-90", else: ""}"}>
            {Phoenix.HTML.raw("&#9662;")}
          </span>
        </button>

        <div :if={!@tasks_collapsed} class="max-h-48 overflow-y-auto">
          <div :if={@tasks == []} class="px-3 py-3 text-center text-xs text-gray-600">
            No tasks
          </div>

          <div class="space-y-0.5 px-1.5 pb-2">
            <div
              :for={task <- @tasks}
              class="flex items-center gap-2 px-2 py-1 rounded hover:bg-gray-900/50"
            >
              <span class="flex-shrink-0 w-4 text-center">{task_status_icon(task.status)}</span>
              <span class="text-xs text-gray-300 truncate flex-1">{task.title}</span>
              <span class="text-xs text-gray-600 truncate max-w-[4rem] text-right">
                {task.owner || ""}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Divider --%>
      <div class="border-t border-gray-800"></div>

      <%!-- Budget Bar --%>
      <div class="flex-shrink-0 px-3 py-3">
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-xs text-gray-500">Budget</span>
          <span class="text-xs text-gray-400 font-mono">
            ${format_decimal(@budget.spent)}&nbsp;/&nbsp;${format_decimal(@budget.limit)}
            <span class={"ml-1 #{budget_pct_color(@budget)}"}>{budget_percentage(@budget)}%</span>
          </span>
        </div>
        <div class="w-full bg-gray-800 rounded-full h-1.5">
          <div
            class={"h-1.5 rounded-full transition-all duration-300 #{budget_bar_color(@budget)}"}
            style={"width: #{min(budget_percentage(@budget), 100)}%"}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Agent color hash ---

  defp agent_color(name) do
    index = :erlang.phash2(name, length(@agent_colors))
    Enum.at(@agent_colors, index)
  end

  # --- Status helpers ---

  defp status_dot_class(:working), do: "bg-green-400 animate-pulse"
  defp status_dot_class(:idle), do: "bg-gray-500"
  defp status_dot_class(:blocked), do: "bg-yellow-400"
  defp status_dot_class(:error), do: "bg-red-400 animate-pulse"
  defp status_dot_class(:waiting_permission), do: "bg-amber-400"
  defp status_dot_class(_), do: "bg-gray-500"

  defp status_text_color(:working), do: "text-green-400"
  defp status_text_color(:idle), do: "text-gray-500"
  defp status_text_color(:blocked), do: "text-yellow-400"
  defp status_text_color(:error), do: "text-red-400"
  defp status_text_color(:waiting_permission), do: "text-amber-400"
  defp status_text_color(_), do: "text-gray-500"

  defp status_label(:working), do: "working"
  defp status_label(:idle), do: "idle"
  defp status_label(:blocked), do: "blocked"
  defp status_label(:error), do: "error"
  defp status_label(:waiting_permission), do: "awaiting"
  defp status_label(_), do: "idle"

  # --- Task status icons ---

  defp task_status_icon(:completed),
    do: Phoenix.HTML.raw(~s(<span class="text-green-400">&#10003;</span>))

  defp task_status_icon(:in_progress),
    do:
      Phoenix.HTML.raw(~s(<span class="text-violet-400 animate-spin inline-block">&#9684;</span>))

  defp task_status_icon(:assigned),
    do: Phoenix.HTML.raw(~s(<span class="text-blue-400">&#8594;</span>))

  defp task_status_icon(:pending),
    do: Phoenix.HTML.raw(~s(<span class="text-gray-500">&#9675;</span>))

  defp task_status_icon(:failed),
    do: Phoenix.HTML.raw(~s(<span class="text-red-400">&#10007;</span>))

  defp task_status_icon(_),
    do: Phoenix.HTML.raw(~s(<span class="text-gray-600">&#8226;</span>))

  # --- Budget helpers ---

  defp budget_percentage(%{spent: spent, limit: limit}) when limit > 0 do
    Float.round(spent / limit * 100, 1)
  end

  defp budget_percentage(_), do: 0.0

  defp budget_bar_color(budget) do
    pct = budget_percentage(budget)

    cond do
      pct >= 80 -> "bg-red-500"
      pct >= 50 -> "bg-yellow-500"
      true -> "bg-green-500"
    end
  end

  defp budget_pct_color(budget) do
    pct = budget_percentage(budget)

    cond do
      pct >= 80 -> "text-red-400"
      pct >= 50 -> "text-yellow-400"
      true -> "text-green-400"
    end
  end

  # --- Formatting helpers ---

  defp format_decimal(n) when is_number(n),
    do: :erlang.float_to_binary(n / 1, decimals: 2)

  defp format_decimal(_), do: "0.00"

  defp format_role(role) when is_atom(role), do: role |> Atom.to_string() |> format_role()
  defp format_role(role) when is_binary(role), do: String.slice(role, 0, 8)
  defp format_role(_), do: "-"
end
