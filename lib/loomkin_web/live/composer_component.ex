defmodule LoomkinWeb.ComposerComponent do
  @moduledoc """
  LiveComponent for the message composer input bar.

  Owns its own UI state (show_agent_picker, schedule_popover, schedule_delay_minutes).
  Receives read-only assigns from the parent LiveView.

  Events that affect parent state are forwarded via:
    send(self(), {:composer_event, event, params})

  Events handled locally:
    toggle_agent_picker, close_agent_picker,
    toggle_scheduler, close_scheduler, set_schedule_delay
  """

  use LoomkinWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_agent_picker, fn -> false end)
      |> assign_new(:schedule_popover, fn -> false end)
      |> assign_new(:schedule_delay_minutes, fn -> 5 end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_agent_picker", _params, socket) do
    {:noreply, assign(socket, show_agent_picker: !socket.assigns.show_agent_picker)}
  end

  def handle_event("close_agent_picker", _params, socket) do
    {:noreply, assign(socket, show_agent_picker: false)}
  end

  def handle_event("toggle_scheduler", _params, socket) do
    {:noreply, assign(socket, schedule_popover: !socket.assigns.schedule_popover)}
  end

  def handle_event("close_scheduler", _params, socket) do
    {:noreply, assign(socket, schedule_popover: false)}
  end

  def handle_event("set_schedule_delay", %{"minutes" => minutes}, socket) do
    {:noreply, assign(socket, schedule_delay_minutes: String.to_integer(minutes))}
  end

  # Forward these events to the parent LiveView
  def handle_event("send_message", params, socket) do
    send(self(), {:composer_event, "send_message", params})
    {:noreply, socket}
  end

  def handle_event("cancel_reply", params, socket) do
    send(self(), {:composer_event, "cancel_reply", params})
    {:noreply, socket}
  end

  def handle_event("select_reply_target", params, socket) do
    send(self(), {:composer_event, "select_reply_target", params})
    {:noreply, assign(socket, show_agent_picker: false)}
  end

  def handle_event("toggle_queue_from_composer", params, socket) do
    send(self(), {:composer_event, "toggle_queue_from_composer", params})
    {:noreply, socket}
  end

  def handle_event("enqueue_message", params, socket) do
    send(self(), {:composer_event, "enqueue_message", params})
    {:noreply, socket}
  end

  def handle_event("inject_guidance", params, socket) do
    send(self(), {:composer_event, "inject_guidance", params})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    agents = assigns[:cached_agents] || []
    assigns = assign(assigns, :picker_agents, agents)

    ~H"""
    <div class="flex-shrink-0 bg-surface-1 border-t border-subtle">
      <.render_last_message_strip last_user_message={@last_user_message} />
      <.render_budget_bar
        cached_budget={@cached_budget}
        budget_pct={@budget_pct}
        budget_bar_color_class={@budget_bar_color_class}
      />
      <form phx-submit="send_message" phx-target={@myself} class="px-3 py-2.5 sm:px-4 sm:py-3">
        <%!-- Reply indicator --%>
        <div
          :if={@reply_target}
          class="flex items-center gap-2 mb-2 px-2.5 py-1.5 rounded-lg animate-fade-in bg-brand-subtle border border-brand"
        >
          <span class="badge px-1.5 py-px text-[10px]">
            {@reply_target.agent}
          </span>
          <span class="text-[11px] text-muted">Replying</span>
          <button
            type="button"
            phx-click="cancel_reply"
            phx-target={@myself}
            class="ml-auto rounded-full p-0.5 transition-colors interactive text-muted"
            data-tooltip="Cancel reply"
            aria-label="Cancel reply"
          >
            <.icon name="hero-x-mark-mini" class="w-3 h-3" />
          </button>
        </div>

        <div class="flex gap-1.5 items-end">
          <%!-- Agent picker button --%>
          <div class="relative flex-shrink-0">
            <button
              type="button"
              phx-click="toggle_agent_picker"
              phx-target={@myself}
              class={[
                "flex items-center justify-center h-9 px-2 rounded-lg transition-all duration-200 press-down bg-transparent border",
                if(@reply_target, do: "border-brand text-brand", else: "border-subtle text-muted")
              ]}
              data-tooltip={
                if @reply_target, do: "Replying to #{@reply_target.agent}", else: "Send to team"
              }
              aria-label={
                if @reply_target, do: "Replying to #{@reply_target.agent}", else: "Send to team"
              }
            >
              <.icon name="hero-at-symbol-mini" class="w-3.5 h-3.5" />
              <span :if={@reply_target} class="text-[11px] font-medium ml-1 max-w-[4rem] truncate">
                {@reply_target.agent}
              </span>
            </button>

            <%!-- Agent picker dropdown --%>
            <div
              :if={@show_agent_picker}
              class="card-elevated absolute bottom-full left-0 mb-2 w-52 max-h-60 overflow-y-auto py-1 z-50 animate-scale-in"
              phx-click-away="close_agent_picker"
              phx-target={@myself}
            >
              <div class="px-2.5 py-1.5 border-b border-subtle">
                <span class="text-[10px] font-medium uppercase tracking-wider text-muted">
                  Send to
                </span>
              </div>
              <button
                type="button"
                phx-click="select_reply_target"
                phx-value-agent="team"
                phx-target={@myself}
                class={"flex items-center gap-2 w-full px-2.5 py-1.5 text-left text-xs transition-colors interactive text-primary " <> if(!@reply_target, do: "bg-surface-3", else: "")}
              >
                <span class="w-1.5 h-1.5 rounded-full flex-shrink-0 bg-emerald-400" />
                <span class="font-medium">Entire Kin</span>
              </button>
              <button
                :for={agent <- @picker_agents}
                type="button"
                phx-click="select_reply_target"
                phx-value-agent={agent.name}
                phx-value-team-id={agent.team_id}
                phx-target={@myself}
                class={"flex items-center gap-2 w-full px-2.5 py-1.5 text-left text-xs transition-colors interactive " <> if(@reply_target && @reply_target.agent == agent.name, do: "bg-surface-3", else: "")}
              >
                <span class={"w-1.5 h-1.5 rounded-full flex-shrink-0 " <> agent_picker_dot_class(agent[:status])} />
                <span class="truncate" style={"color: #{agent_color(agent.name)};"}>
                  {agent.name}
                </span>
                <span class="ml-auto text-[10px] text-muted">
                  {agent[:role] || agent[:status]}
                </span>
              </button>
            </div>
          </div>

          <%!-- Queue button (only shown when replying to an agent) --%>
          <div :if={@reply_target} class="relative flex-shrink-0">
            <button
              type="button"
              phx-click="toggle_queue_from_composer"
              phx-target={@myself}
              class="flex items-center justify-center h-9 px-2 rounded-lg transition-all duration-200 press-down border border-subtle text-muted bg-transparent"
              data-tooltip={"View #{@reply_target.agent}'s message queue"}
              aria-label={"View #{@reply_target.agent}'s message queue"}
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M2 4.75A.75.75 0 012.75 4h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 4.75zm0 10.5a.75.75 0 01.75-.75h7.5a.75.75 0 010 1.5h-7.5a.75.75 0 01-.75-.75zM2 10a.75.75 0 01.75-.75h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 10z" />
              </svg>
            </button>
          </div>

          <%!-- Textarea --%>
          <div class="flex-1 relative">
            <textarea
              name="text"
              rows="1"
              aria-label="Message to team"
              placeholder={
                if @reply_target,
                  do: "Reply to #{@reply_target.agent}...",
                  else: "What should we work on?"
              }
              class="w-full rounded-lg px-3 py-2 text-sm resize-none overflow-hidden focus:outline-none transition-all duration-200 bg-surface-0 border border-subtle text-primary caret-brand"
              phx-hook="ShiftEnterSubmit"
              id="message-input"
            ><%= @input_text %></textarea>
          </div>

          <%!-- Send/Cancel buttons --%>
          <button
            :if={@status != :thinking}
            type="submit"
            class={"flex items-center justify-center w-9 h-9 rounded-lg transition-all duration-200 press-down " <>
              if(@status == :idle, do: "text-white", else: "cursor-not-allowed")}
            style={
              if @status == :idle,
                do: "background: var(--brand);",
                else: "background: var(--surface-2); color: var(--text-muted);"
            }
            disabled={@status != :idle}
            data-tooltip="Send message"
            aria-label="Send message"
          >
            <svg
              class="w-3.5 h-3.5"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M6 12L3.269 3.126A59.768 59.768 0 0121.485 12 59.77 59.77 0 013.27 20.876L5.999 12zm0 0h7.5"
              />
            </svg>
          </button>
          <button
            :if={@status == :thinking}
            type="button"
            phx-click="cancel"
            class="flex items-center justify-center w-9 h-9 rounded-lg transition-all duration-200 press-down"
            style="background: rgba(248, 113, 113, 0.15); color: #f87171; border: 1px solid rgba(248, 113, 113, 0.3);"
            data-tooltip="Stop generation"
            aria-label="Stop generation"
          >
            <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
              <rect x="6" y="6" width="12" height="12" rx="2" />
            </svg>
          </button>

          <%!-- Schedule button --%>
          <div :if={@status != :thinking} class="relative flex-shrink-0">
            <button
              type="button"
              phx-click="toggle_scheduler"
              phx-target={@myself}
              class={[
                "flex items-center justify-center w-9 h-9 rounded-lg transition-all duration-200 press-down bg-transparent border",
                if(@schedule_popover, do: "border-brand text-brand", else: "border-subtle text-muted")
              ]}
              data-tooltip="Schedule message"
              aria-label="Schedule message"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>

            <%!-- Schedule popover --%>
            <LoomkinWeb.ScheduleMessageComponent.schedule_popover
              :if={@schedule_popover}
              target_agent={if(@reply_target, do: @reply_target.agent)}
              content={@input_text}
              delay_minutes={@schedule_delay_minutes}
              scheduled_messages={@scheduled_messages}
            />
          </div>

          <%!-- Enqueue button (add to queue without sending) --%>
          <button
            :if={@status != :thinking && @reply_target}
            type="button"
            phx-click="enqueue_message"
            phx-target={@myself}
            class="flex items-center justify-center w-9 h-9 rounded-lg transition-all duration-200 press-down border border-subtle text-muted bg-transparent"
            data-tooltip={"Add to #{@reply_target.agent}'s queue"}
            aria-label={"Add to #{@reply_target.agent}'s queue"}
          >
            <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
            </svg>
          </button>

          <%!-- Inject guidance button (when agent is working) --%>
          <button
            :if={
              @status != :thinking && @reply_target &&
                agent_is_working?(assigns[:agent_cards] || %{}, @reply_target.agent)
            }
            type="button"
            phx-click="inject_guidance"
            phx-target={@myself}
            class="flex items-center gap-1 h-9 px-2.5 rounded-lg transition-all duration-200 press-down text-[11px] font-medium"
            style="border: 1px solid rgba(52, 211, 153, 0.3); color: #34d399; background: rgba(52, 211, 153, 0.08);"
            data-tooltip={"Guide #{@reply_target.agent} without pausing"}
          >
            <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
              <path
                fill-rule="evenodd"
                d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.274 1.765 11.307 11.307 0 00.757.433c.11.057.19.095.237.117l.025.012.006.003zm.28-12.182a1.25 1.25 0 10-1.94 1.577 1.25 1.25 0 001.94-1.577zM10 11a2 2 0 100-4 2 2 0 000 4z"
                clip-rule="evenodd"
              />
            </svg>
            Guide
          </button>
        </div>

        <div class="flex items-center gap-3 mt-1 pl-0.5">
          <span class="text-[10px] text-muted opacity-60">
            <kbd class="font-mono text-[9px]">&#8679;&#9166;</kbd> new line
          </span>
          <span class="text-[10px] text-muted opacity-60">
            <kbd class="font-mono text-[9px]">/</kbd> focus
          </span>
        </div>
      </form>
    </div>
    """
  end

  # --- Sub-renders ---

  defp render_budget_bar(assigns) do
    budget = assigns[:cached_budget] || %{spent: 0.0, limit: 5.0}
    pct = assigns[:budget_pct] || 0
    color_class = assigns[:budget_bar_color_class] || "bg-emerald-500"

    assigns =
      assigns
      |> assign(:budget, budget)
      |> assign(:pct, pct)
      |> assign(:color_class, color_class)

    ~H"""
    <div class="flex-shrink-0 px-4 py-2 flex items-center gap-3 border-t border-subtle bg-surface-1">
      <span class="text-[10px] font-semibold text-muted uppercase tracking-widest flex-shrink-0">
        Budget
      </span>
      <div class="flex-1 rounded-full h-1.5 overflow-hidden bg-surface-3">
        <div
          class={["h-full rounded-full", @color_class]}
          style={"width: #{min(@pct, 100)}%; transition: width 0.5s cubic-bezier(0.4, 0, 0.2, 1);"}
        >
        </div>
      </div>
      <span class="text-[11px] font-mono tabular-nums flex-shrink-0 text-secondary">
        ${format_decimal_cost(@budget.spent)}
        <span class="text-muted">/ ${format_decimal_cost(@budget.limit)}</span>
      </span>
    </div>
    """
  end

  defp render_last_message_strip(%{last_user_message: nil} = assigns) do
    ~H""
  end

  defp render_last_message_strip(assigns) do
    ~H"""
    <div class="flex-shrink-0 px-4 py-1.5 flex items-center gap-2 overflow-hidden border-t border-subtle bg-surface-1">
      <span class="text-[10px] font-semibold text-muted uppercase tracking-widest flex-shrink-0">
        You
      </span>
      <span class="text-[10px] flex-shrink-0 text-muted">
        &rarr;
      </span>
      <span class="text-[10px] font-medium flex-shrink-0 text-brand">
        {@last_user_message.to}
      </span>
      <span class="text-[11px] truncate flex-1 min-w-0 text-secondary">
        {@last_user_message.text}
      </span>
    </div>
    """
  end

  # --- Helpers ---

  defp agent_picker_dot_class(:idle), do: "bg-green-400"
  defp agent_picker_dot_class(:thinking), do: "bg-violet-400 status-dot-thinking"
  defp agent_picker_dot_class(:executing_tool), do: "bg-blue-400"
  defp agent_picker_dot_class(:error), do: "bg-red-400"
  defp agent_picker_dot_class(:blocked), do: "bg-amber-400"
  defp agent_picker_dot_class(_), do: "bg-gray-400"

  defp agent_color(name), do: LoomkinWeb.AgentColors.agent_color(name)

  defp format_decimal_cost(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_decimal_cost(n) when is_integer(n), do: "#{n}.00"
  defp format_decimal_cost(_), do: "0.00"

  defp agent_is_working?(agent_cards, agent_name) do
    case Map.get(agent_cards, agent_name) do
      %{status: :working} -> true
      _ -> false
    end
  end
end
