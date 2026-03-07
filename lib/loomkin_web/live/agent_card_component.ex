defmodule LoomkinWeb.AgentCardComponent do
  @moduledoc """
  LiveComponent that renders a single agent's workbench card in
  the mission control UI. Each agent gets one card that updates in-place,
  showing status, current activity, and action buttons.

  As a LiveComponent, only the card whose assigns change will re-render,
  and MDEx markdown rendering is memoized so it only runs when content
  actually changes.
  """

  use LoomkinWeb, :live_component

  @tool_config %{
    "file_read" => %{icon: "📄", color: "#818cf8"},
    "file_write" => %{icon: "✍", color: "#34d399"},
    "file_edit" => %{icon: "✎", color: "#fbbf24"},
    "file_search" => %{icon: "🔍", color: "#22d3ee"},
    "content_search" => %{icon: "🔍", color: "#22d3ee"},
    "directory_list" => %{icon: "📁", color: "#a78bfa"},
    "shell" => %{icon: "⚡", color: "#f472b6"},
    "git" => %{icon: "📈", color: "#fb923c"}
  }
  @default_tool_config %{icon: "⚙", color: "#71717a"}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       card: nil,
       focused: false,
       team_id: nil,
       model: nil,
       rendered_content: "",
       prev_content: nil,
       prev_content_type: nil,
       prev_focused: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    card = socket.assigns.card
    focused = socket.assigns.focused

    new_content = card && card.latest_content
    new_content_type = card && card.content_type
    old_content = socket.assigns.prev_content
    old_content_type = socket.assigns.prev_content_type
    old_focused = socket.assigns.prev_focused

    socket =
      if new_content != old_content || new_content_type != old_content_type ||
           focused != old_focused do
        rendered = render_card_markdown(format_content(new_content, focused))

        assign(socket,
          rendered_content: rendered,
          prev_content: new_content,
          prev_content_type: new_content_type,
          prev_focused: focused
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    color = LoomkinWeb.AgentColors.agent_color(assigns.card.name)
    assigns = assign(assigns, :agent_color, color)

    ~H"""
    <div
      id={"agent-card-#{@card.name}"}
      phx-click="focus_card_agent"
      phx-value-agent={@card.name}
      class={[
        "group relative animate-fade-in flex flex-col card-grain overflow-hidden",
        if(@focused,
          do: "card-brand card-focused-glow h-full rounded-lg",
          else: "min-h-[140px] cursor-pointer card-elevated hover-lift rounded-lg"
        ),
        card_state_class(@card.content_type, @card.status)
      ]}
      style={card_style(@card.content_type, @card.last_tool, @agent_color, @focused)}
    >
      <%!-- Top accent line — agent identity color --%>
      <div
        :if={!@focused}
        class="h-[2px] w-full flex-shrink-0"
        style={"background: linear-gradient(90deg, #{@agent_color}, #{@agent_color}40);"}
      />

      <div class="p-4 flex flex-col flex-1 min-h-0">
        <%!-- Question overlay --%>
        <div
          :if={@card.pending_question}
          class="absolute inset-0 z-10 rounded-lg bg-gradient-to-br from-violet-900/30 to-purple-900/20 border border-violet-500/30 p-4 flex flex-col overflow-auto"
        >
          <div class="flex items-center gap-2 mb-3">
            <div class="w-6 h-6 rounded-lg bg-violet-500/20 flex items-center justify-center flex-shrink-0">
              <svg class="w-3.5 h-3.5 text-violet-400" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <p class="text-xs font-semibold text-violet-300 truncate">
              {@card.pending_question.agent_name} needs your input
            </p>
          </div>

          <p class="text-sm text-gray-200 mb-3 leading-relaxed line-clamp-2">
            {@card.pending_question.question}
          </p>

          <div class="flex flex-wrap gap-1.5 mt-auto">
            <button
              :for={option <- @card.pending_question.options}
              phx-click="ask_user_answer"
              phx-value-question-id={@card.pending_question.question_id}
              phx-value-answer={option}
              class="px-3 py-1.5 text-xs font-medium text-violet-300 bg-violet-500/10 hover:bg-violet-500/25 border border-violet-500/30 hover:border-violet-400/50 rounded-lg transition-all duration-200 cursor-pointer"
            >
              {option}
            </button>
            <button
              phx-click="ask_user_answer"
              phx-value-question-id={@card.pending_question.question_id}
              phx-value-answer="__collective__"
              class="px-3 py-1.5 text-xs font-medium text-amber-300 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 hover:border-amber-400/50 rounded-lg transition-all duration-200 cursor-pointer"
            >
              Let the collective decide
            </button>
          </div>
        </div>

        <%!-- Header: avatar, name, role, action buttons --%>
        <div class="flex items-center gap-2.5">
          <%!-- Agent avatar — colored initial --%>
          <div
            class="w-7 h-7 rounded-md flex items-center justify-center flex-shrink-0 text-[11px] font-bold"
            style={"background: #{@agent_color}18; color: #{@agent_color};"}
          >
            {agent_initial(@card.name)}
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-1.5">
              <span class={[
                "w-1.5 h-1.5 rounded-full flex-shrink-0 status-dot-transition",
                status_dot_class(@card.status)
              ]} />
              <span
                class="text-[13px] font-semibold truncate"
                style={"color: #{@agent_color};"}
              >
                {@card.name}
              </span>
            </div>
            <span class="text-[10px] text-muted leading-none">
              {format_role(@card.role)}
              <span :if={@model} class="font-mono opacity-50 ml-1">
                {format_model(@model)}
              </span>
            </span>
          </div>

          <%!-- Action buttons (visible on hover) --%>
          <div
            class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100"
            style="transition: opacity var(--transition-base);"
          >
            <button
              phx-click="reply_to_card_agent"
              phx-value-agent={@card.name}
              phx-value-team-id={@team_id}
              title={"Reply to #{@card.name}"}
              class="text-muted hover:text-brand p-1 rounded-md hover:bg-surface-3 flex-shrink-0"
              style="transition: color var(--transition-base), background var(--transition-base);"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M7.707 3.293a1 1 0 010 1.414L5.414 7H11a7 7 0 017 7v2a1 1 0 11-2 0v-2a5 5 0 00-5-5H5.414l2.293 2.293a1 1 0 11-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
            <button
              :if={@card.status == :working}
              phx-click="pause_card_agent"
              phx-value-agent={@card.name}
              phx-value-team-id={@team_id}
              title={"Pause #{@card.name}"}
              class="text-muted hover:text-amber-400 p-1 rounded-md hover:bg-surface-3 flex-shrink-0"
              style="transition: color var(--transition-base), background var(--transition-base);"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM7 8a1 1 0 012 0v4a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v4a1 1 0 102 0V8a1 1 0 00-1-1z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
            <button
              :if={@card.status == :paused}
              phx-click="resume_card_agent"
              phx-value-agent={@card.name}
              phx-value-team-id={@team_id}
              title={"Resume #{@card.name}"}
              class="text-muted hover:text-green-400 p-1 rounded-md hover:bg-surface-3 flex-shrink-0"
              style="transition: color var(--transition-base), background var(--transition-base);"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
            <button
              :if={@card.status == :paused}
              phx-click="steer_card_agent"
              phx-value-agent={@card.name}
              phx-value-team-id={@team_id}
              title={"Steer #{@card.name}"}
              class="text-muted hover:text-brand p-1 rounded-md hover:bg-surface-3 flex-shrink-0"
              style="transition: color var(--transition-base), background var(--transition-base);"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Capability bars --%>
        <.capability_bars
          :if={@team_id && !@focused}
          team_id={@team_id}
          agent_name={@card.name}
        />

        <%!-- Content area --%>
        <div class={["mt-3 flex-1 min-h-0", @focused && "overflow-auto"]}>
          <%= case @card.content_type do %>
            <% :thinking -> %>
              <div
                class={[
                  "text-xs leading-relaxed agent-card-content rounded-md px-2.5 py-2",
                  !@focused && "line-clamp-4"
                ]}
                style={"color: var(--text-secondary); background: #{@agent_color}06;"}
              >
                {@rendered_content}
              </div>
            <% :last_thinking -> %>
              <div
                class={[
                  "text-xs leading-relaxed opacity-40 agent-card-content",
                  !@focused && "line-clamp-3"
                ]}
                style="color: var(--text-secondary);"
              >
                {@rendered_content}
              </div>
            <% :message -> %>
              <div
                class={[
                  "text-xs leading-relaxed agent-card-content",
                  !@focused && "line-clamp-4"
                ]}
                style="color: var(--text-secondary);"
              >
                {@rendered_content}
              </div>
            <% _ -> %>
              <%= if @card.status == :complete do %>
                <div class="flex items-center gap-1.5 text-xs text-emerald-400/80">
                  <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                    <path
                      fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span>Done</span>
                </div>
              <% else %>
                <div class="flex items-center gap-1.5 text-xs text-muted">
                  <span
                    class="w-1 h-1 rounded-full flex-shrink-0"
                    style={"background: #{@agent_color}40;"}
                  />
                  <span class="italic">Waiting</span>
                </div>
              <% end %>
          <% end %>

          <%!-- Last tool --%>
          <div
            :if={@card.last_tool}
            class="mt-2 flex items-center gap-1.5 px-2 py-1 rounded-md"
            style="background: var(--surface-3);"
          >
            <span
              class="text-[10px]"
              style={"color: #{tool_config(@card.last_tool.name).color}"}
            >
              {tool_config(@card.last_tool.name).icon}
            </span>
            <span class="text-[10px] font-mono truncate text-muted">
              {@card.last_tool.target || @card.last_tool.name}
            </span>
          </div>
        </div>

        <%!-- Footer: current task --%>
        <div
          :if={@card.current_task}
          class="mt-2 pt-2 flex items-center gap-2"
          style={"border-top: 1px solid #{@agent_color}12;"}
        >
          <span
            class="text-[10px] uppercase tracking-wide flex-shrink-0 font-medium"
            style={"color: #{@agent_color}80;"}
          >
            Task
          </span>
          <span class="text-[11px] truncate flex-1 font-mono text-secondary">
            {@card.current_task}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Card state animation class ---

  defp card_state_class(:thinking, _status), do: "card-breathing"
  defp card_state_class(:tool_call, _status), do: "card-tool-active"
  defp card_state_class(:streaming, _status), do: "card-streaming"
  defp card_state_class(_content_type, :paused), do: "agent-card-paused"
  defp card_state_class(_content_type, :blocked), do: "agent-card-blocked"
  defp card_state_class(_content_type, :error), do: "card-error"
  defp card_state_class(nil, :idle), do: "card-idle"
  defp card_state_class(_content_type, _status), do: nil

  # --- Card style (inline) — combines agent tint + tool-active state ---

  defp card_style(:tool_call, %{name: name}, _agent_color, _focused) when is_binary(name) do
    color = tool_config(name).color
    "border-color: #{color}; box-shadow: 0 0 10px #{hex_to_rgba(color, 0.1)};"
  end

  defp card_style(_content_type, _last_tool, _agent_color, true = _focused), do: nil

  defp card_style(_content_type, _last_tool, agent_color, _focused) do
    "background: linear-gradient(145deg, var(--surface-2), var(--surface-3)); border-color: #{agent_color}15;"
  end

  # --- Agent identity helpers ---

  defp agent_initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp agent_initial(_), do: "?"

  # --- Status helpers ---

  defp status_dot_class(:working), do: "bg-green-400 agent-dot-working"
  defp status_dot_class(:idle), do: "bg-zinc-500"
  defp status_dot_class(:blocked), do: "bg-amber-400 agent-dot-thinking"
  defp status_dot_class(:paused), do: "bg-blue-400 animate-pulse"
  defp status_dot_class(:error), do: "bg-red-400 agent-dot-error"
  defp status_dot_class(:waiting_permission), do: "bg-amber-400 agent-dot-thinking"
  defp status_dot_class(:complete), do: "bg-emerald-400"
  defp status_dot_class(_), do: "bg-zinc-500"

  # --- Capability bars ---

  defp capability_bars(assigns) do
    caps =
      Loomkin.Teams.Capabilities.get_capabilities(assigns.team_id, assigns.agent_name)
      |> Enum.take(3)

    assigns = assign(assigns, :caps, caps)

    ~H"""
    <div :if={@caps != []} class="mt-1.5 flex items-center gap-3">
      <div
        :for={cap <- @caps}
        class="flex items-center gap-1 min-w-0"
        title={"#{cap.task_type}: #{Float.round(cap.score, 1)}"}
      >
        <span class="text-[9px] text-muted truncate w-8">
          {cap.task_type |> to_string() |> String.slice(0, 4)}
        </span>
        <div class="capability-bar w-10">
          <div
            class="capability-bar-fill"
            style={"width: #{cap_bar_width(cap.score)}%; background: var(--brand-hover);"}
          />
        </div>
      </div>
    </div>
    """
  end

  defp cap_bar_width(score) when score <= 0, do: 5
  defp cap_bar_width(score), do: min(round(score / 5.0 * 100), 100)

  # --- Tool lookup helpers ---

  defp tool_config(name) when is_binary(name),
    do: Map.get(@tool_config, name, @default_tool_config)

  defp tool_config(_), do: @default_tool_config

  # --- Formatting helpers ---

  defp format_role(role) when is_atom(role) or is_binary(role) do
    role |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_role(_), do: "-"

  defp format_content(nil, _focused), do: ""

  defp format_content(content, focused) when is_binary(content) do
    trimmed = String.trim(content)
    if focused, do: trimmed, else: String.slice(trimmed, 0, 500)
  end

  defp format_content(_, _focused), do: ""

  defp render_card_markdown(""), do: ""

  defp render_card_markdown(content) when is_binary(content) do
    doc =
      MDEx.new(render: [unsafe_: true])
      |> MDEx.Document.put_markdown(content)

    case MDEx.to_html(doc) do
      {:ok, html} ->
        Phoenix.HTML.raw(html)

      _ ->
        {:safe, escaped} = Phoenix.HTML.html_escape(content)
        Phoenix.HTML.raw("<p>#{escaped}</p>")
    end
  end

  defp render_card_markdown(_), do: ""

  # --- Model helpers ---

  defp format_model(nil), do: ""

  defp format_model(model) when is_binary(model) do
    model
    |> String.split("/")
    |> List.last()
    |> String.split(":")
    |> List.last()
    |> String.slice(0, 15)
  end

  defp format_model(_), do: ""

  defp hex_to_rgba("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>, alpha) do
    "rgba(#{String.to_integer(r, 16)}, #{String.to_integer(g, 16)}, #{String.to_integer(b, 16)}, #{alpha})"
  end

  defp hex_to_rgba(color, _alpha), do: color
end
