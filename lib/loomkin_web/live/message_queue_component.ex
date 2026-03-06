defmodule LoomkinWeb.MessageQueueComponent do
  @moduledoc """
  Slide-out drawer that shows an agent's pending message queue.
  Supports viewing, editing, deleting, multi-select squash, and
  drag-and-drop reordering of queued messages.
  """

  use Phoenix.Component

  import LoomkinWeb.CoreComponents, only: [icon: 1]

  attr :queue, :list, required: true
  attr :agent_name, :string, required: true
  attr :team_id, :string, required: true
  attr :selected_ids, :any, default: %MapSet{}
  attr :editing_id, :string, default: nil

  def queue_drawer(assigns) do
    selected_count = MapSet.size(assigns.selected_ids)

    assigns =
      assigns
      |> Phoenix.Component.assign(:selected, assigns.selected_ids)
      |> Phoenix.Component.assign(:selected_count, selected_count)

    ~H"""
    <div
      id={"queue-drawer-#{@agent_name}"}
      class="fixed inset-y-0 right-0 z-50 w-80 flex flex-col animate-slide-in-right"
      style="background: var(--surface-1); border-left: 1px solid var(--border-subtle); box-shadow: -4px 0 24px rgba(0,0,0,0.3);"
      phx-click-away="close_queue_drawer"
    >
      <%!-- Header --%>
      <div
        class="flex items-center gap-2 px-4 py-3 flex-shrink-0"
        style="border-bottom: 1px solid var(--border-subtle);"
      >
        <.icon name="hero-queue-list-mini" class="w-4 h-4 text-indigo-400" />
        <span class="text-sm font-medium" style="color: var(--text-primary);">
          {@agent_name}
        </span>
        <span class="text-[10px] px-1.5 py-0.5 rounded-full font-medium bg-indigo-500/15 text-indigo-400">
          {length(@queue)} queued
        </span>
        <div class="flex-1"></div>
        <button
          phx-click="close_queue_drawer"
          class="p-1 rounded-md interactive"
          style="color: var(--text-muted);"
          title="Close"
        >
          <.icon name="hero-x-mark-mini" class="w-4 h-4" />
        </button>
      </div>

      <%!-- Multi-select toolbar --%>
      <div
        :if={@selected_count > 0}
        class="flex items-center gap-2 px-4 py-2 flex-shrink-0"
        style="border-bottom: 1px solid var(--border-subtle); background: var(--brand-subtle);"
      >
        <span class="text-xs font-medium" style="color: var(--text-brand);">
          {@selected_count} selected
        </span>
        <div class="flex-1"></div>
        <button
          phx-click="squash_queued"
          phx-value-agent={@agent_name}
          class="text-[11px] px-2 py-1 rounded-md font-medium text-indigo-300 bg-indigo-500/15 hover:bg-indigo-500/25 transition-colors"
        >
          Squash
        </button>
        <button
          phx-click="delete_selected_queued"
          phx-value-agent={@agent_name}
          class="text-[11px] px-2 py-1 rounded-md font-medium text-red-300 bg-red-500/15 hover:bg-red-500/25 transition-colors"
        >
          Delete
        </button>
        <button
          phx-click="deselect_all_queued"
          class="text-[11px] px-2 py-1 rounded-md font-medium interactive"
          style="color: var(--text-muted);"
        >
          Clear
        </button>
      </div>

      <%!-- Queue list --%>
      <div
        id={"queue-list-#{@agent_name}"}
        class="flex-1 overflow-auto"
        phx-hook="SortableQueue"
        phx-update="ignore"
        data-agent={@agent_name}
      >
        <%= if @queue == [] do %>
          <div class="flex flex-col items-center justify-center py-12 gap-3">
            <.icon name="hero-inbox-mini" class="w-8 h-8 text-zinc-600" />
            <span class="text-xs text-muted">No messages queued</span>
          </div>
        <% else %>
          <div
            :for={msg <- @queue}
            id={"queue-item-#{msg.id}"}
            class="group/item px-4 py-3 cursor-default"
            style="border-bottom: 1px solid var(--border-subtle);"
            data-id={msg.id}
          >
            <%= if @editing_id == msg.id do %>
              <%!-- Inline editor --%>
              <form
                phx-submit="save_queued_edit"
                id={"queue-edit-form-#{msg.id}"}
                class="flex flex-col gap-2"
              >
                <input type="hidden" name="agent" value={@agent_name} />
                <input type="hidden" name="message_id" value={msg.id} />
                <textarea
                  name="content"
                  rows="3"
                  class="w-full rounded-lg px-3 py-2 text-xs resize-none focus:outline-none"
                  style="background: var(--surface-0); border: 1px solid var(--border-brand); color: var(--text-primary); caret-color: var(--brand);"
                  autofocus
                  id={"queue-edit-#{msg.id}"}
                >{msg.content}</textarea>
                <div class="flex gap-1.5 justify-end">
                  <button
                    type="button"
                    phx-click="cancel_queued_edit"
                    class="text-[11px] px-2.5 py-1 rounded-md interactive"
                    style="color: var(--text-muted); border: 1px solid var(--border-subtle);"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="text-[11px] px-2.5 py-1 rounded-md font-medium text-white"
                    style="background: var(--brand);"
                  >
                    Save
                  </button>
                </div>
              </form>
            <% else %>
              <div class="flex items-start gap-2">
                <%!-- Drag handle --%>
                <span class="flex-shrink-0 mt-0.5 cursor-grab opacity-0 group-hover/item:opacity-40 transition-opacity drag-handle">
                  <.icon name="hero-bars-3-mini" class="w-3.5 h-3.5 text-muted" />
                </span>

                <%!-- Checkbox --%>
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected, msg.id)}
                  phx-click="toggle_queue_select"
                  phx-value-agent={@agent_name}
                  phx-value-id={msg.id}
                  class="flex-shrink-0 mt-0.5 w-3.5 h-3.5 rounded border-zinc-600 bg-zinc-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                />

                <div class="flex-1 min-w-0">
                  <%!-- Priority + source badges --%>
                  <div class="flex items-center gap-1.5 mb-1">
                    <span class={[
                      "w-1.5 h-1.5 rounded-full flex-shrink-0",
                      priority_dot_class(msg.priority)
                    ]}>
                    </span>
                    <span class={[
                      "text-[10px] px-1.5 py-0.5 rounded font-medium",
                      source_badge_class(msg.source)
                    ]}>
                      {msg.source}
                    </span>
                    <span
                      id={"queue-time-#{msg.id}"}
                      class="text-[10px] text-muted ml-auto flex-shrink-0"
                      phx-hook="LocalTime"
                      data-utc-time={if(msg.queued_at, do: DateTime.to_iso8601(msg.queued_at))}
                      data-format="relative"
                    >
                    </span>
                  </div>

                  <%!-- Content preview --%>
                  <p
                    class="text-xs leading-relaxed line-clamp-2"
                    style="color: var(--text-secondary);"
                  >
                    {msg.content}
                  </p>
                </div>

                <%!-- Action buttons --%>
                <div class="flex items-center gap-0.5 flex-shrink-0 opacity-0 group-hover/item:opacity-100 transition-opacity">
                  <button
                    phx-click="start_queued_edit"
                    phx-value-id={msg.id}
                    title="Edit"
                    class="p-1 rounded-md interactive"
                    style="color: var(--text-muted);"
                  >
                    <.icon name="hero-pencil-mini" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="delete_queued"
                    phx-value-agent={@agent_name}
                    phx-value-id={msg.id}
                    title="Delete"
                    class="p-1 rounded-md interactive text-red-400/60 hover:text-red-400"
                  >
                    <.icon name="hero-trash-mini" class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp priority_dot_class(:urgent), do: "bg-red-400"
  defp priority_dot_class(:high), do: "bg-amber-400"
  defp priority_dot_class(_), do: "bg-zinc-500"

  defp source_badge_class(:user), do: "bg-blue-500/15 text-blue-400"
  defp source_badge_class(:system), do: "bg-purple-500/15 text-purple-400"
  defp source_badge_class(:peer), do: "bg-green-500/15 text-green-400"
  defp source_badge_class(:scheduled), do: "bg-amber-500/15 text-amber-400"
  defp source_badge_class(_), do: "bg-zinc-500/15 text-zinc-400"
end
