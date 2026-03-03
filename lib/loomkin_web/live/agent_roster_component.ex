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
    {:ok, assign(socket, Map.put_new(assigns, :channel_bindings, []))}
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
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-sm font-semibold text-violet-400 truncate">{@team_id}</span>
          {channel_badges(assigns)}
        </div>
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

  # --- Channel badge helpers ---

  defp channel_badges(assigns) do
    telegram_count =
      Enum.count(assigns.channel_bindings, &(&1.channel == :telegram))

    discord_count =
      Enum.count(assigns.channel_bindings, &(&1.channel == :discord))

    assigns =
      assigns
      |> assign(:telegram_count, telegram_count)
      |> assign(:discord_count, discord_count)

    ~H"""
    <span
      :if={@telegram_count > 0}
      class="inline-flex items-center gap-0.5 text-[10px] text-sky-400 bg-sky-400/10 px-1.5 py-0.5 rounded-full"
      title={"#{@telegram_count} Telegram binding#{if @telegram_count > 1, do: "s", else: ""}"}
    >
      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4.64 6.8c-.15 1.58-.8 5.42-1.13 7.19-.14.75-.42 1-.68 1.03-.58.05-1.02-.38-1.58-.75-.88-.58-1.38-.94-2.23-1.5-.99-.65-.35-1.01.22-1.59.15-.15 2.71-2.48 2.76-2.69a.2.2 0 00-.05-.18c-.06-.05-.14-.03-.21-.02-.09.02-1.49.95-4.22 2.79-.4.27-.76.41-1.08.4-.36-.01-1.04-.2-1.55-.37-.63-.2-1.12-.31-1.08-.66.02-.18.27-.36.74-.55 2.92-1.27 4.86-2.11 5.83-2.51 2.78-1.16 3.35-1.36 3.73-1.36.08 0 .27.02.39.12.1.08.13.19.14.27-.01.06.01.24 0 .38z" />
      </svg>
      {if @telegram_count > 1, do: @telegram_count, else: ""}
    </span>
    <span
      :if={@discord_count > 0}
      class="inline-flex items-center gap-0.5 text-[10px] text-indigo-400 bg-indigo-400/10 px-1.5 py-0.5 rounded-full"
      title={"#{@discord_count} Discord binding#{if @discord_count > 1, do: "s", else: ""}"}
    >
      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="currentColor">
        <path d="M20.317 4.37a19.791 19.791 0 00-4.885-1.515.074.074 0 00-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 00-5.487 0 12.64 12.64 0 00-.617-1.25.077.077 0 00-.079-.037A19.736 19.736 0 003.677 4.37a.07.07 0 00-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 00.031.057 19.9 19.9 0 005.993 3.03.078.078 0 00.084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 00-.041-.106 13.107 13.107 0 01-1.872-.892.077.077 0 01-.008-.128 10.2 10.2 0 00.372-.292.074.074 0 01.077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 01.078.01c.12.098.246.198.373.292a.077.077 0 01-.006.127 12.299 12.299 0 01-1.873.892.077.077 0 00-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 00.084.028 19.839 19.839 0 006.002-3.03.077.077 0 00.032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 00-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
      </svg>
      {if @discord_count > 1, do: @discord_count, else: ""}
    </span>
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
