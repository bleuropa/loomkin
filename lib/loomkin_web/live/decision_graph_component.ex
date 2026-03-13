defmodule LoomkinWeb.DecisionGraphComponent do
  @moduledoc "LiveComponent for interactive decision graph with tree view and fullscreen SVG."

  use LoomkinWeb, :live_component

  alias Loomkin.Decisions.Graph
  alias Loomkin.Decisions.Pulse

  @layer_order %{
    goal: 0,
    revisit: 1,
    decision: 1,
    option: 2,
    action: 3,
    outcome: 4,
    observation: 4
  }

  @node_width 160
  @node_height 56
  @layer_gap 120
  @node_gap 180

  # Softer node type colors (reduced saturation ~20%)
  @node_type_colors %{
    goal: {"#1a2f4d", "#5b8fd4"},
    decision: {"#3d351a", "#d4a930"},
    option: {"#1a3128", "#3dba6e"},
    action: {"#271c42", "#9366d4"},
    outcome: {"#1a3232", "#2aada0"},
    observation: {"#1f2937", "#8896a8"},
    revisit: {"#33241a", "#e08840"}
  }

  # Legend display labels
  @node_type_labels [
    {:goal, "Goal"},
    {:decision, "Decision"},
    {:option, "Option"},
    {:action, "Action"},
    {:outcome, "Outcome"},
    {:observation, "Observation"},
    {:revisit, "Revisit"}
  ]

  # Depth-based colors for tree indent guides
  @depth_colors %{
    0 => "#5b8fd4",
    1 => "#d4a930",
    2 => "#3dba6e",
    3 => "#9366d4",
    4 => "#2aada0"
  }

  # Forward edge types that define parent-child hierarchy
  @forward_edge_types [:leads_to, :chosen, :requires, :enables, :supports]

  # Pulse cache TTL in seconds
  @pulse_ttl_seconds 30

  @decision_signals [
    "decision.node.added",
    "decision.pivot.created",
    "decision.logged"
  ]

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       nodes: [],
       edges: [],
       positioned: [],
       tree: [],
       pulse: nil,
       pulse_data: nil,
       pulse_generated_at: nil,
       selected_node: nil,
       agent_filter: nil,
       visible_types: MapSet.new([:goal, :decision, :observation, :revisit]),
       new_node_ids: MapSet.new(),
       collapsed_ids: MapSet.new(),
       fullscreen: false,
       refresh_ref: nil,
       reload_timer: nil,
       subscribed: false,
       svg_width: 800,
       svg_height: 400
     )}
  end

  @impl true
  def update(assigns, socket) do
    prev_session_id = socket.assigns[:session_id]
    prev_team_id = socket.assigns[:team_id]
    prev_refresh_ref = socket.assigns[:refresh_ref]

    socket = assign(socket, assigns)

    # Subscribe to decision signals once (double-subscription guard)
    socket =
      if !socket.assigns[:subscribed] do
        Enum.each(@decision_signals, &Loomkin.Signals.subscribe/1)
        assign(socket, :subscribed, true)
      else
        socket
      end

    session_id = socket.assigns[:session_id]
    team_id = socket.assigns[:team_id]
    refresh_ref = socket.assigns[:refresh_ref]

    session_or_team_changed =
      session_id != prev_session_id or team_id != prev_team_id

    refreshed =
      refresh_ref != nil and refresh_ref != prev_refresh_ref

    cond do
      session_or_team_changed ->
        do_load_graph(socket, session_id, team_id, MapSet.new())

      refreshed ->
        prev_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)
        do_load_graph(socket, session_id, team_id, prev_node_ids)

      true ->
        {:ok, socket}
    end
  end

  # --- Signal handlers (debounced reload) ---

  def handle_info(%Jido.Signal{type: "decision.node.added", data: data}, socket) do
    if data[:team_id] == socket.assigns[:team_id] do
      {:noreply, schedule_reload(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Jido.Signal{type: "decision.pivot.created", data: data}, socket) do
    if data[:team_id] == socket.assigns[:team_id] do
      {:noreply, schedule_reload(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Jido.Signal{type: "decision.logged", data: data}, socket) do
    if data[:team_id] == socket.assigns[:team_id] do
      {:noreply, schedule_reload(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:reload_graph_data, socket) do
    prev_node_ids = MapSet.new(socket.assigns.nodes, & &1.id)

    case do_load_graph(
           socket |> assign(:reload_timer, nil),
           socket.assigns[:session_id],
           socket.assigns[:team_id],
           prev_node_ids
         ) do
      {:ok, socket} -> {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp do_load_graph(socket, session_id, team_id, prev_node_ids) do
    {nodes, edges, pulse} = load_graph_data(session_id, team_id, socket)
    node_ids = MapSet.new(nodes, & &1.id)

    new_node_ids = MapSet.difference(node_ids, prev_node_ids)

    # Filter edges to only those connecting our nodes
    relevant_edges =
      Enum.filter(edges, fn e ->
        MapSet.member?(node_ids, e.from_node_id) and MapSet.member?(node_ids, e.to_node_id)
      end)

    # Unique agents present in this graph
    agents =
      nodes
      |> Enum.map(& &1.agent_name)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Detect conflict node IDs
    conflict_ids = detect_conflicts(nodes, relevant_edges)

    # Apply agent filter
    agent_filter = socket.assigns[:agent_filter]

    visible_types =
      socket.assigns[:visible_types] ||
        MapSet.new([:goal, :decision, :observation, :revisit])

    {visible_nodes, visible_edges} =
      nodes
      |> then(&apply_agent_filter(&1, relevant_edges, agent_filter))
      |> then(fn {n, e} -> apply_type_filter(n, e, visible_types) end)

    positioned = layout_nodes(visible_nodes)
    {svg_w, svg_h} = compute_svg_dimensions(positioned)
    tree = build_tree(visible_nodes, visible_edges)

    pulse_assigns = [pulse_data: pulse, pulse_generated_at: System.monotonic_time(:second)]

    {:ok,
     assign(
       socket,
       [
         {:nodes, nodes},
         {:edges, relevant_edges},
         {:positioned, positioned},
         {:tree, tree},
         {:pulse, pulse},
         {:agents, agents},
         {:conflict_ids, conflict_ids},
         {:new_node_ids, new_node_ids},
         {:visible_edges, visible_edges},
         {:svg_width, max(svg_w, 400)},
         {:svg_height, max(svg_h, 200)}
         | pulse_assigns
       ]
     )}
  end

  @impl true
  def handle_event("select_node", %{"id" => node_id}, socket) do
    selected =
      if socket.assigns.selected_node && socket.assigns.selected_node.id == node_id do
        nil
      else
        Enum.find(socket.assigns.nodes, &(&1.id == node_id))
      end

    {:noreply, assign(socket, selected_node: selected)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, selected_node: nil)}
  end

  def handle_event("filter_agent", %{"agent" => ""}, socket) do
    {:noreply, recompute_visible(socket, nil)}
  end

  def handle_event("filter_agent", %{"agent" => agent_name}, socket) do
    {:noreply, recompute_visible(socket, agent_name)}
  end

  def handle_event("toggle_type", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)
    visible = socket.assigns.visible_types

    visible =
      if MapSet.member?(visible, type),
        do: MapSet.delete(visible, type),
        else: MapSet.put(visible, type)

    {:noreply, recompute_visible(socket, socket.assigns.agent_filter, visible)}
  end

  def handle_event("show_all_types", _params, socket) do
    all = MapSet.new([:goal, :decision, :option, :action, :outcome, :observation, :revisit])
    {:noreply, recompute_visible(socket, socket.assigns.agent_filter, all)}
  end

  def handle_event("toggle_tree_node", %{"id" => node_id}, socket) do
    collapsed_ids = socket.assigns.collapsed_ids

    collapsed_ids =
      if MapSet.member?(collapsed_ids, node_id) do
        MapSet.delete(collapsed_ids, node_id)
      else
        MapSet.put(collapsed_ids, node_id)
      end

    {:noreply, assign(socket, collapsed_ids: collapsed_ids)}
  end

  def handle_event("open_fullscreen", _params, socket) do
    {:noreply, assign(socket, fullscreen: true)}
  end

  def handle_event("close_fullscreen", _params, socket) do
    {:noreply, assign(socket, fullscreen: false)}
  end

  # ──────────────────────────────────────────────
  # Render
  # ──────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-gray-950 text-gray-100">
      <div class="px-3 py-2.5 border-b border-gray-800 flex items-center justify-between">
        <h3 class="text-[10px] font-semibold text-gray-500 uppercase tracking-widest">
          Decision Graph
        </h3>
        <button
          :if={@nodes != []}
          phx-click="open_fullscreen"
          phx-target={@myself}
          class="p-1 rounded hover:bg-gray-800 text-gray-500 hover:text-gray-300 transition-colors"
          title="Open full graph view"
        >
          <.icon name="hero-arrows-pointing-out-mini" class="w-3.5 h-3.5" />
        </button>
      </div>

      <%!-- Agent filter buttons --%>
      <div :if={@agents != []} class="px-3 py-2 border-b border-gray-800 flex flex-wrap gap-1">
        <button
          phx-click="filter_agent"
          phx-value-agent=""
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border transition-colors duration-200",
            if(@agent_filter == nil,
              do: "border-violet-400 text-violet-400 bg-violet-400/10",
              else: "border-gray-700 text-gray-400 hover:border-gray-500"
            )
          ]}
        >
          All
        </button>
        <button
          :for={agent <- @agents}
          phx-click="filter_agent"
          phx-value-agent={agent}
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border flex items-center gap-1 transition-colors duration-200",
            if(@agent_filter == agent,
              do: "bg-white/10",
              else: "hover:border-gray-500"
            )
          ]}
          style={
            if @agent_filter == agent do
              "border-color: #{agent_color(agent)}; color: #{agent_color(agent)}"
            else
              "border-color: #374151; color: #9ca3af"
            end
          }
        >
          <span
            class="inline-block w-2 h-2 rounded-full"
            style={"background-color: #{agent_color(agent)}"}
          />
          {agent}
        </button>
      </div>

      <%!-- Node type toggle buttons --%>
      <div class="px-3 py-2 border-b border-gray-800 flex flex-wrap gap-1">
        <button
          phx-click="show_all_types"
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border transition-colors",
            if(MapSet.size(@visible_types) == 7,
              do: "border-violet-400 text-violet-400 bg-violet-400/10",
              else: "border-gray-700 text-gray-400 hover:border-gray-500"
            )
          ]}
        >
          All
        </button>
        <button
          :for={type <- [:goal, :decision, :action, :option, :outcome, :observation, :revisit]}
          phx-click="toggle_type"
          phx-value-type={type}
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border flex items-center gap-1 transition-colors",
            if(MapSet.member?(@visible_types, type),
              do: "border-current bg-current/10",
              else: "border-gray-700 text-gray-400 hover:border-gray-500"
            )
          ]}
          style={
            if MapSet.member?(@visible_types, type),
              do: "color: #{type_color(type)}",
              else: ""
          }
        >
          <span
            class="inline-block w-2 h-2 rounded-full"
            style={"background-color: #{type_color(type)}"}
          />
          {type}
        </button>
      </div>

      <%!-- Main content: tree view --%>
      <div class="flex-1 overflow-auto relative">
        <%= if @nodes == [] do %>
          <div class="flex flex-col items-center justify-center h-full px-6 text-center">
            <div class="w-12 h-12 rounded-full bg-gray-800/60 flex items-center justify-center mb-3">
              <.icon name="hero-share" class="w-6 h-6 text-gray-600" />
            </div>
            <p class="text-gray-400 text-sm font-medium mb-1">No decisions recorded yet</p>
            <p class="text-gray-600 text-xs max-w-xs leading-relaxed">
              The decision graph tracks goals, decisions, options, and outcomes as your coding session progresses.
            </p>
          </div>
        <% else %>
          <div class="py-1.5">
            <.tree_node
              :for={item <- @tree}
              item={item}
              collapsed_ids={@collapsed_ids}
              selected_node={@selected_node}
              conflict_ids={@conflict_ids}
              new_node_ids={@new_node_ids}
              edges={@edges}
              nodes={@nodes}
              myself={@myself}
            />
          </div>
        <% end %>
      </div>

      <div :if={@pulse} class="px-3 py-2 border-t border-gray-800 text-[10px] text-gray-600">
        {format_pulse(@pulse)}
      </div>

      <%!-- Fullscreen SVG overlay --%>
      <.fullscreen_overlay
        :if={@fullscreen}
        positioned={@positioned}
        visible_edges={@visible_edges}
        selected_node={@selected_node}
        conflict_ids={@conflict_ids}
        new_node_ids={@new_node_ids}
        agents={@agents}
        agent_filter={@agent_filter}
        visible_types={@visible_types}
        edges={@edges}
        nodes={@nodes}
        svg_width={@svg_width}
        svg_height={@svg_height}
        myself={@myself}
      />
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # Tree view sub-components
  # ──────────────────────────────────────────────

  defp tree_node(assigns) do
    node = assigns.item.node
    depth = assigns.item.depth
    children = assigns.item.children
    has_children = children != []
    collapsed = MapSet.member?(assigns.collapsed_ids, node.id)
    selected = assigns.selected_node && assigns.selected_node.id == node.id
    conflict = MapSet.member?(assigns.conflict_ids, node.id)
    is_new = MapSet.member?(assigns.new_node_ids, node.id)
    depth_color = depth_color(depth)
    type_stroke = node_type_stroke(node.node_type)

    assigns =
      assigns
      |> assign(:node, node)
      |> assign(:depth, depth)
      |> assign(:children, children)
      |> assign(:has_children, has_children)
      |> assign(:collapsed, collapsed)
      |> assign(:selected, selected)
      |> assign(:conflict, conflict)
      |> assign(:is_new, is_new)
      |> assign(:depth_color, depth_color)
      |> assign(:type_stroke, type_stroke)

    ~H"""
    <div>
      <div
        class={[
          "flex items-center gap-1.5 py-1 group cursor-pointer transition-colors duration-100",
          "hover:bg-gray-800/40",
          @selected && "bg-gray-800/60",
          @is_new && "bg-gray-800/30"
        ]}
        style={"padding-left: #{8 + @depth * 20}px; padding-right: 8px"}
      >
        <%!-- Expand/collapse chevron --%>
        <%= if @has_children do %>
          <button
            phx-click="toggle_tree_node"
            phx-value-id={@node.id}
            phx-target={@myself}
            class="p-0.5 rounded hover:bg-gray-700/50 text-gray-500 hover:text-gray-300 flex-shrink-0"
          >
            <.icon
              name={if @collapsed, do: "hero-chevron-right-mini", else: "hero-chevron-down-mini"}
              class="w-3.5 h-3.5"
            />
          </button>
        <% else %>
          <span class="w-[18px] flex-shrink-0" />
        <% end %>

        <%!-- Node type dot --%>
        <span
          class={[
            "inline-block w-2 h-2 rounded-full flex-shrink-0",
            @conflict && "ring-1 ring-red-500"
          ]}
          style={"background-color: #{@type_stroke}"}
        />

        <%!-- Title & metadata --%>
        <button
          phx-click="select_node"
          phx-value-id={@node.id}
          phx-target={@myself}
          class="flex items-center gap-1.5 min-w-0 flex-1 text-left"
        >
          <span class={[
            "text-xs truncate",
            if(@selected, do: "text-gray-100 font-medium", else: "text-gray-300")
          ]}>
            {@node.title}
          </span>
          <span class="text-[10px] text-gray-600 flex-shrink-0">
            {Atom.to_string(@node.node_type)}
          </span>
          <span
            :if={@node.status != :active}
            class={["text-[10px] flex-shrink-0", status_text_class(@node.status)]}
          >
            {Atom.to_string(@node.status)}
          </span>
          <span
            :if={@node.agent_name}
            class="text-[10px] flex-shrink-0"
            style={"color: #{agent_color(@node.agent_name)}"}
          >
            {@node.agent_name}
          </span>
          <span
            :if={@node.confidence}
            class={["text-[10px] font-medium flex-shrink-0", confidence_text_class(@node.confidence)]}
          >
            {@node.confidence}%
          </span>
        </button>
      </div>

      <%!-- Inline detail panel --%>
      <.inline_node_detail
        :if={@selected}
        node={@node}
        edges={@edges}
        nodes={@nodes}
        depth={@depth}
        myself={@myself}
      />

      <%!-- Children with colored left border --%>
      <div
        :if={@has_children && !@collapsed}
        class="border-l-2"
        style={"margin-left: #{18 + @depth * 20}px; border-color: #{@depth_color}"}
      >
        <.tree_node
          :for={child <- @children}
          item={child}
          collapsed_ids={@collapsed_ids}
          selected_node={@selected_node}
          conflict_ids={@conflict_ids}
          new_node_ids={@new_node_ids}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # Fullscreen SVG overlay
  # ──────────────────────────────────────────────

  defp fullscreen_overlay(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 bg-gray-950/95 backdrop-blur-sm flex flex-col"
      phx-window-keydown="close_fullscreen"
      phx-key="Escape"
      phx-target={@myself}
    >
      <div class="flex items-center justify-between px-4 py-3 border-b border-gray-800">
        <h3 class="text-sm font-semibold text-gray-300">Decision Graph</h3>
        <div class="flex items-center gap-2">
          <%!-- Agent filter in fullscreen --%>
          <div :if={@agents != []} class="flex flex-wrap gap-1">
            <button
              phx-click="filter_agent"
              phx-value-agent=""
              phx-target={@myself}
              class={[
                "px-2 py-1 text-xs rounded-full border transition-colors duration-200",
                if(@agent_filter == nil,
                  do: "border-violet-400 text-violet-400 bg-violet-400/10",
                  else: "border-gray-700 text-gray-400 hover:border-gray-500"
                )
              ]}
            >
              All
            </button>
            <button
              :for={agent <- @agents}
              phx-click="filter_agent"
              phx-value-agent={agent}
              phx-target={@myself}
              class={[
                "px-2 py-1 text-xs rounded-full border flex items-center gap-1 transition-colors duration-200",
                if(@agent_filter == agent,
                  do: "bg-white/10",
                  else: "hover:border-gray-500"
                )
              ]}
              style={
                if @agent_filter == agent do
                  "border-color: #{agent_color(agent)}; color: #{agent_color(agent)}"
                else
                  "border-color: #374151; color: #9ca3af"
                end
              }
            >
              <span
                class="inline-block w-2 h-2 rounded-full"
                style={"background-color: #{agent_color(agent)}"}
              />
              {agent}
            </button>
          </div>

          <button
            phx-click="close_fullscreen"
            phx-target={@myself}
            class="p-1.5 rounded-lg hover:bg-gray-800 text-gray-400 hover:text-gray-200 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
      </div>

      <%!-- Node type toggle buttons (fullscreen) --%>
      <div class="px-4 py-2 border-b border-gray-800 flex flex-wrap gap-1">
        <button
          phx-click="show_all_types"
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border transition-colors",
            if(MapSet.size(@visible_types) == 7,
              do: "border-violet-400 text-violet-400 bg-violet-400/10",
              else: "border-gray-700 text-gray-400 hover:border-gray-500"
            )
          ]}
        >
          All
        </button>
        <button
          :for={type <- [:goal, :decision, :action, :option, :outcome, :observation, :revisit]}
          phx-click="toggle_type"
          phx-value-type={type}
          phx-target={@myself}
          class={[
            "px-2 py-1 text-xs rounded-full border flex items-center gap-1 transition-colors",
            if(MapSet.member?(@visible_types, type),
              do: "border-current bg-current/10",
              else: "border-gray-700 text-gray-400 hover:border-gray-500"
            )
          ]}
          style={
            if MapSet.member?(@visible_types, type),
              do: "color: #{type_color(type)}",
              else: ""
          }
        >
          <span
            class="inline-block w-2 h-2 rounded-full"
            style={"background-color: #{type_color(type)}"}
          />
          {type}
        </button>
      </div>

      <div class="flex-1 overflow-auto p-4 relative">
        <svg
          width={@svg_width}
          height={@svg_height}
          viewBox={"0 0 #{@svg_width} #{@svg_height}"}
          class="block"
        >
          <defs>
            <marker
              id="fs-arrowhead-gray"
              markerWidth="8"
              markerHeight="6"
              refX="8"
              refY="3"
              orient="auto"
            >
              <polygon points="0 0, 8 3, 0 6" fill="#6b7280" />
            </marker>
            <marker
              id="fs-arrowhead-green"
              markerWidth="8"
              markerHeight="6"
              refX="8"
              refY="3"
              orient="auto"
            >
              <polygon points="0 0, 8 3, 0 6" fill="#22c55e" />
            </marker>
            <marker
              id="fs-arrowhead-red"
              markerWidth="8"
              markerHeight="6"
              refX="8"
              refY="3"
              orient="auto"
            >
              <polygon points="0 0, 8 3, 0 6" fill="#ef4444" />
            </marker>
            <marker
              id="fs-arrowhead-orange"
              markerWidth="8"
              markerHeight="6"
              refX="8"
              refY="3"
              orient="auto"
            >
              <polygon points="0 0, 8 3, 0 6" fill="#f97316" />
            </marker>
          </defs>

          <.graph_edge
            :for={edge <- @visible_edges}
            edge={edge}
            positioned={@positioned}
            marker_prefix="fs-"
          />

          <.graph_node
            :for={pos <- @positioned}
            pos={pos}
            selected={@selected_node && @selected_node.id == pos.node.id}
            conflict={MapSet.member?(@conflict_ids, pos.node.id)}
            is_new={MapSet.member?(@new_node_ids, pos.node.id)}
            myself={@myself}
          />
        </svg>

        <%!-- Node detail panel (fullscreen) --%>
        <.node_detail
          :if={@selected_node}
          node={@selected_node}
          edges={@edges}
          nodes={@nodes}
          myself={@myself}
        />
      </div>

      <%!-- Legends --%>
      <div class="border-t border-gray-800 px-4 py-2 flex flex-wrap gap-x-6 gap-y-1.5">
        <div class="flex flex-wrap gap-x-3 gap-y-1.5">
          <span class="text-[10px] text-gray-600 uppercase tracking-wider mr-1">Types:</span>
          <div :for={{type, label} <- node_type_labels()} class="flex items-center gap-1.5">
            <span
              class="inline-block w-2.5 h-2.5 rounded-sm border"
              style={"background-color: #{node_type_fill(type)}; border-color: #{node_type_stroke(type)}"}
            />
            <span class="text-[10px] text-gray-500">{label}</span>
          </div>
        </div>
        <div :if={@agents != []} class="flex flex-wrap gap-x-3 gap-y-1.5">
          <span class="text-[10px] text-gray-600 uppercase tracking-wider mr-1">Agents:</span>
          <div :for={agent <- @agents} class="flex items-center gap-1.5">
            <span
              class="inline-block w-2 h-2 rounded-full"
              style={"background-color: #{agent_color(agent)}"}
            />
            <span class="text-[10px] text-gray-500">{agent}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # SVG sub-components
  # ──────────────────────────────────────────────

  defp graph_node(assigns) do
    node = assigns.pos.node
    x = assigns.pos.x
    y = assigns.pos.y

    # Agent-based coloring takes priority when agent_name is present
    {fill, stroke} =
      if node.agent_name do
        color = agent_color(node.agent_name)
        {color <> "20", color}
      else
        node_colors(node.node_type, node.status)
      end

    stroke_style = status_stroke_style(node.status)
    tooltip = if node.agent_name, do: "#{node.title} (#{node.agent_name})", else: node.title

    assigns =
      assigns
      |> assign(:x, x)
      |> assign(:y, y)
      |> assign(:fill, fill)
      |> assign(:stroke, stroke)
      |> assign(:stroke_style, stroke_style)
      |> assign(:node, node)
      |> assign(:tooltip, tooltip)
      |> assign(:w, @node_width)
      |> assign(:h, @node_height)

    ~H"""
    <g
      phx-click="select_node"
      phx-value-id={@node.id}
      phx-target={@myself}
      class={["cursor-pointer", @is_new && "graph-node-new"]}
      role="button"
      tabindex="0"
    >
      <title>{@tooltip}</title>
      <%!-- Conflict glow ring --%>
      <rect
        :if={@conflict}
        x={@x - 3}
        y={@y - 3}
        width={@w + 6}
        height={@h + 6}
        rx="10"
        fill="none"
        stroke="#ef4444"
        stroke-width="2"
        class="conflict-glow"
      />
      <%!-- New node glow ring --%>
      <rect
        :if={@is_new}
        x={@x - 3}
        y={@y - 3}
        width={@w + 6}
        height={@h + 6}
        rx="10"
        fill="none"
        stroke={@stroke}
        stroke-width="1.5"
        class="graph-node-glow"
      />
      <rect
        x={@x}
        y={@y}
        width={@w}
        height={@h}
        rx="8"
        fill={@fill}
        stroke={@stroke}
        stroke-width={if @selected, do: "3", else: "1.5"}
        stroke-dasharray={@stroke_style}
      />
      <text
        x={@x + @w / 2}
        y={@y + 22}
        text-anchor="middle"
        fill="#e5e7eb"
        font-size="12"
        font-weight="600"
      >
        {truncate_text(@node.title, 18)}
      </text>
      <text
        x={@x + @w / 2}
        y={@y + 38}
        text-anchor="middle"
        fill="#9ca3af"
        font-size="10"
      >
        {Atom.to_string(@node.node_type)}
      </text>
      <%!-- Agent name label --%>
      <text
        :if={@node.agent_name}
        x={@x + @w / 2}
        y={@y + 50}
        text-anchor="middle"
        fill={agent_color(@node.agent_name)}
        font-size="8"
      >
        {@node.agent_name}
      </text>
      <%!-- Confidence badge --%>
      <g :if={@node.confidence}>
        <circle
          cx={@x + @w - 8}
          cy={@y + 8}
          r="10"
          fill={confidence_color(@node.confidence)}
        />
        <text
          x={@x + @w - 8}
          y={@y + 12}
          text-anchor="middle"
          fill="white"
          font-size="9"
          font-weight="bold"
        >
          {@node.confidence}
        </text>
      </g>
    </g>
    """
  end

  defp graph_edge(assigns) do
    edge = assigns.edge
    positioned = assigns.positioned
    prefix = Map.get(assigns, :marker_prefix, "")

    from_pos = Enum.find(positioned, fn p -> p.node.id == edge.from_node_id end)
    to_pos = Enum.find(positioned, fn p -> p.node.id == edge.to_node_id end)

    if from_pos && to_pos do
      x1 = from_pos.x + @node_width / 2
      y1 = from_pos.y + @node_height
      x2 = to_pos.x + @node_width / 2
      y2 = to_pos.y

      mid_y = (y1 + y2) / 2
      path_d = "M#{x1},#{y1} C#{x1},#{mid_y} #{x2},#{mid_y} #{x2},#{y2}"
      {color, marker} = edge_style(edge.edge_type)

      assigns =
        assigns
        |> assign(:path_d, path_d)
        |> assign(:color, color)
        |> assign(:marker, prefix <> marker)

      ~H"""
      <path
        d={@path_d}
        fill="none"
        stroke={@color}
        stroke-width="1.5"
        marker-end={"url(##{@marker})"}
      />
      """
    else
      ~H""
    end
  end

  defp node_detail(assigns) do
    node = assigns.node

    connected_edges =
      Enum.filter(assigns.edges, fn e ->
        e.from_node_id == node.id or e.to_node_id == node.id
      end)

    assigns = assign(assigns, :connected_edges, connected_edges)

    ~H"""
    <div class="absolute top-2 right-2 w-72 bg-gray-900 border border-gray-700/50 rounded-xl shadow-2xl z-20 overflow-hidden animate-scale-in">
      <div class="flex items-center justify-between px-3 py-2.5 border-b border-gray-800 bg-gray-900/80">
        <span class="text-sm font-semibold text-gray-200 truncate">{@node.title}</span>
        <button
          phx-click="close_detail"
          phx-target={@myself}
          class="text-gray-500 hover:text-gray-300 ml-2 p-0.5 rounded hover:bg-gray-800 transition-colors"
        >
          <.icon name="hero-x-mark-mini" class="w-4 h-4" />
        </button>
      </div>

      <div class="px-3 py-3 space-y-2.5 text-xs max-h-64 overflow-y-auto">
        <div class="flex gap-2">
          <span class="text-gray-500">Type:</span>
          <span class="text-gray-300 bg-gray-800/60 rounded px-1.5 py-0.5">
            {Atom.to_string(@node.node_type)}
          </span>
        </div>
        <div class="flex gap-2">
          <span class="text-gray-500">Status:</span>
          <span class={status_text_class(@node.status)}>{Atom.to_string(@node.status)}</span>
        </div>
        <div :if={@node.agent_name} class="flex gap-2 items-center">
          <span class="text-gray-500">Agent:</span>
          <span class="flex items-center gap-1">
            <span
              class="inline-block w-2 h-2 rounded-full"
              style={"background-color: #{agent_color(@node.agent_name)}"}
            />
            <span style={"color: #{agent_color(@node.agent_name)}"}>{@node.agent_name}</span>
          </span>
        </div>
        <div :if={@node.confidence} class="flex gap-2">
          <span class="text-gray-500">Confidence:</span>
          <span class="text-gray-300">{@node.confidence}%</span>
        </div>
        <div :if={@node.description} class="pt-1">
          <span class="text-gray-500 block mb-1">Description:</span>
          <p class="text-gray-400 leading-relaxed">{@node.description}</p>
        </div>
        <div :if={@connected_edges != []} class="pt-1">
          <span class="text-gray-500 block mb-1">Connections:</span>
          <div :for={edge <- @connected_edges} class="flex items-center gap-1 text-gray-400 py-0.5">
            <span class={edge_text_class(edge.edge_type)}>{Atom.to_string(edge.edge_type)}</span>
            <span>&rarr;</span>
            <span>{find_connected_title(edge, @node, @nodes)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp inline_node_detail(assigns) do
    node = assigns.node

    connected_edges =
      Enum.filter(assigns.edges, fn e ->
        e.from_node_id == node.id or e.to_node_id == node.id
      end)

    assigns = assign(assigns, :connected_edges, connected_edges)

    ~H"""
    <div
      class="mx-2 my-1 bg-gray-900 border border-gray-700/50 rounded-lg shadow-lg overflow-hidden"
      style={"margin-left: #{18 + @depth * 20}px"}
    >
      <div class="flex items-center justify-between px-3 py-2 border-b border-gray-800 bg-gray-900/80">
        <span class="text-xs font-semibold text-gray-200 truncate">{@node.title}</span>
        <button
          phx-click="close_detail"
          phx-target={@myself}
          class="text-gray-500 hover:text-gray-300 ml-2 p-0.5 rounded hover:bg-gray-800 transition-colors"
        >
          <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
        </button>
      </div>

      <div class="px-3 py-2.5 space-y-2 text-xs">
        <div class="flex gap-2">
          <span class="text-gray-500">Type:</span>
          <span class="text-gray-300 bg-gray-800/60 rounded px-1.5 py-0.5">
            {Atom.to_string(@node.node_type)}
          </span>
        </div>
        <div class="flex gap-2">
          <span class="text-gray-500">Status:</span>
          <span class={status_text_class(@node.status)}>{Atom.to_string(@node.status)}</span>
        </div>
        <div :if={@node.agent_name} class="flex gap-2 items-center">
          <span class="text-gray-500">Agent:</span>
          <span class="flex items-center gap-1">
            <span
              class="inline-block w-2 h-2 rounded-full"
              style={"background-color: #{agent_color(@node.agent_name)}"}
            />
            <span style={"color: #{agent_color(@node.agent_name)}"}>{@node.agent_name}</span>
          </span>
        </div>
        <div :if={@node.confidence} class="flex gap-2">
          <span class="text-gray-500">Confidence:</span>
          <span class="text-gray-300">{@node.confidence}%</span>
        </div>
        <div :if={@node.description} class="pt-1">
          <span class="text-gray-500 block mb-1">Description:</span>
          <p class="text-gray-400 leading-relaxed">{@node.description}</p>
        </div>
        <div :if={@connected_edges != []} class="pt-1">
          <span class="text-gray-500 block mb-1">Connections:</span>
          <div :for={edge <- @connected_edges} class="flex items-center gap-1 text-gray-400 py-0.5">
            <span class={edge_text_class(edge.edge_type)}>{Atom.to_string(edge.edge_type)}</span>
            <span>&rarr;</span>
            <span>{find_connected_title(edge, @node, @nodes)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────
  # Tree building
  # ──────────────────────────────────────────────

  defp build_tree(nodes, edges) do
    # Build adjacency from forward edges only
    forward_edges = Enum.filter(edges, &(&1.edge_type in @forward_edge_types))

    children_map =
      Enum.reduce(forward_edges, %{}, fn edge, acc ->
        Map.update(acc, edge.from_node_id, [edge.to_node_id], &[edge.to_node_id | &1])
      end)

    # IDs that have a parent (appear as to_node_id in forward edges)
    child_ids = MapSet.new(forward_edges, & &1.to_node_id)

    # Roots: nodes without incoming forward edges
    node_map = Map.new(nodes, &{&1.id, &1})

    roots =
      nodes
      |> Enum.reject(&MapSet.member?(child_ids, &1.id))
      |> Enum.sort_by(&Map.get(@layer_order, &1.node_type, 2))

    # If no roots found, use all nodes as roots
    roots = if roots == [], do: Enum.sort_by(nodes, & &1.inserted_at), else: roots

    # Walk tree recursively
    {tree, _visited} =
      Enum.reduce(roots, {[], MapSet.new()}, fn root, {acc, visited} ->
        {subtree, visited} = walk_tree(root, children_map, node_map, visited, 0)
        {acc ++ [subtree], visited}
      end)

    tree
  end

  defp walk_tree(node, children_map, node_map, visited, depth) do
    visited = MapSet.put(visited, node.id)

    child_ids = Map.get(children_map, node.id, [])

    {children, visited} =
      child_ids
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.reduce({[], visited}, fn child_id, {acc, vis} ->
        case Map.get(node_map, child_id) do
          nil ->
            {acc, vis}

          child_node ->
            {subtree, vis} = walk_tree(child_node, children_map, node_map, vis, depth + 1)
            {acc ++ [subtree], vis}
        end
      end)

    item = %{node: node, children: children, depth: depth}
    {item, visited}
  end

  # ──────────────────────────────────────────────
  # Layout
  # ──────────────────────────────────────────────

  defp layout_nodes(nodes) do
    grouped =
      nodes
      |> Enum.group_by(fn n -> Map.get(@layer_order, n.node_type, 2) end)
      |> Enum.sort_by(fn {layer, _} -> layer end)

    Enum.flat_map(grouped, fn {layer_y, layer_nodes} ->
      layer_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, x_idx} ->
        %{
          node: node,
          x: 40 + x_idx * @node_gap,
          y: 40 + layer_y * @layer_gap
        }
      end)
    end)
  end

  defp compute_svg_dimensions(positioned) do
    if positioned == [] do
      {400, 200}
    else
      max_x = Enum.max_by(positioned, & &1.x) |> Map.get(:x)
      max_y = Enum.max_by(positioned, & &1.y) |> Map.get(:y)
      {max_x + @node_width + 60, max_y + @node_height + 60}
    end
  end

  # ──────────────────────────────────────────────
  # Styling helpers
  # ──────────────────────────────────────────────

  defp depth_color(depth) do
    Map.get(@depth_colors, min(depth, 4))
  end

  defp node_colors(node_type, _status) do
    case Map.get(@node_type_colors, node_type) do
      {fill, stroke} -> {fill, stroke}
      nil -> {"#1f2937", "#6b7280"}
    end
  end

  defp node_type_fill(type) do
    case Map.get(@node_type_colors, type) do
      {fill, _} -> fill
      nil -> "#1f2937"
    end
  end

  defp node_type_stroke(type) do
    case Map.get(@node_type_colors, type) do
      {_, stroke} -> stroke
      nil -> "#6b7280"
    end
  end

  defp node_type_labels, do: @node_type_labels

  defp status_stroke_style(:active), do: ""
  defp status_stroke_style(:superseded), do: "6,4"
  defp status_stroke_style(:abandoned), do: "2,4"
  defp status_stroke_style(_), do: ""

  defp confidence_color(c) when c >= 70, do: "#22c55e"
  defp confidence_color(c) when c >= 40, do: "#eab308"
  defp confidence_color(_), do: "#ef4444"

  defp confidence_text_class(c) when c >= 70, do: "text-green-400"
  defp confidence_text_class(c) when c >= 40, do: "text-yellow-400"
  defp confidence_text_class(_), do: "text-red-400"

  defp edge_style(:chosen), do: {"#22c55e", "arrowhead-green"}
  defp edge_style(:rejected), do: {"#ef4444", "arrowhead-red"}
  defp edge_style(:supersedes), do: {"#f97316", "arrowhead-orange"}
  defp edge_style(_), do: {"#6b7280", "arrowhead-gray"}

  defp status_text_class(:active), do: "text-green-400"
  defp status_text_class(:superseded), do: "text-yellow-400"
  defp status_text_class(:abandoned), do: "text-red-400"
  defp status_text_class(_), do: "text-gray-400"

  defp type_color(:goal), do: "#facc15"
  defp type_color(:decision), do: "#a78bfa"
  defp type_color(:action), do: "#60a5fa"
  defp type_color(:option), do: "#34d399"
  defp type_color(:outcome), do: "#f472b6"
  defp type_color(:observation), do: "#fb923c"
  defp type_color(:revisit), do: "#f87171"
  defp type_color(_), do: "#71717a"

  defp edge_text_class(:chosen), do: "text-green-400"
  defp edge_text_class(:rejected), do: "text-red-400"
  defp edge_text_class(:supersedes), do: "text-orange-400"
  defp edge_text_class(_), do: "text-gray-500"

  # ──────────────────────────────────────────────
  # Agent helpers
  # ──────────────────────────────────────────────

  defp agent_color(agent_name), do: LoomkinWeb.AgentColors.agent_color(agent_name)

  defp detect_conflicts(nodes, edges) do
    supersedes_pairs =
      edges
      |> Enum.filter(&(&1.edge_type == :supersedes))
      |> Enum.flat_map(fn edge ->
        from = Enum.find(nodes, &(&1.id == edge.from_node_id))
        to = Enum.find(nodes, &(&1.id == edge.to_node_id))

        if from && to && from.agent_name && to.agent_name && from.agent_name != to.agent_name do
          [from.id, to.id]
        else
          []
        end
      end)

    title_conflicts =
      nodes
      |> Enum.filter(& &1.agent_name)
      |> Enum.group_by(& &1.title)
      |> Enum.flat_map(fn {_title, group} ->
        agents = Enum.map(group, & &1.agent_name) |> Enum.uniq()
        has_superseded = Enum.any?(group, &(&1.status == :superseded))

        if length(agents) > 1 and has_superseded do
          Enum.map(group, & &1.id)
        else
          []
        end
      end)

    MapSet.new(supersedes_pairs ++ title_conflicts)
  end

  defp recompute_visible(socket, agent_filter) do
    recompute_visible(socket, agent_filter, socket.assigns.visible_types)
  end

  defp recompute_visible(socket, agent_filter, visible_types) do
    {nodes_after_agent, edges_after_agent} =
      apply_agent_filter(socket.assigns.nodes, socket.assigns.edges, agent_filter)

    {visible_nodes, visible_edges} =
      apply_type_filter(nodes_after_agent, edges_after_agent, visible_types)

    positioned = layout_nodes(visible_nodes)
    {svg_w, svg_h} = compute_svg_dimensions(positioned)
    tree = build_tree(visible_nodes, visible_edges)

    assign(socket,
      agent_filter: agent_filter,
      visible_types: visible_types,
      positioned: positioned,
      visible_edges: visible_edges,
      tree: tree,
      svg_width: max(svg_w, 400),
      svg_height: max(svg_h, 200)
    )
  end

  defp schedule_reload(socket) do
    if timer = socket.assigns[:reload_timer] do
      Process.cancel_timer(timer)
    end

    timer = Process.send_after(self(), :reload_graph_data, 500)
    assign(socket, :reload_timer, timer)
  end

  defp apply_agent_filter(nodes, edges, nil), do: {nodes, edges}

  defp apply_agent_filter(nodes, edges, agent_name) do
    filtered_nodes = Enum.filter(nodes, &(&1.agent_name == agent_name))
    filtered_ids = MapSet.new(filtered_nodes, & &1.id)

    filtered_edges =
      Enum.filter(edges, fn e ->
        MapSet.member?(filtered_ids, e.from_node_id) and
          MapSet.member?(filtered_ids, e.to_node_id)
      end)

    {filtered_nodes, filtered_edges}
  end

  defp apply_type_filter(nodes, edges, visible_types) do
    filtered_nodes = Enum.filter(nodes, &MapSet.member?(visible_types, &1.node_type))
    filtered_ids = MapSet.new(filtered_nodes, & &1.id)

    filtered_edges =
      Enum.filter(edges, fn e ->
        MapSet.member?(filtered_ids, e.from_node_id) and
          MapSet.member?(filtered_ids, e.to_node_id)
      end)

    {filtered_nodes, filtered_edges}
  end

  # ──────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────

  defp truncate_text(nil, _), do: ""

  defp truncate_text(text, max) do
    if String.length(text) > max do
      String.slice(text, 0, max - 1) <> "..."
    else
      text
    end
  end

  defp find_connected_title(edge, current_node, nodes) do
    target_id =
      if edge.from_node_id == current_node.id do
        edge.to_node_id
      else
        edge.from_node_id
      end

    case Enum.find(nodes, &(&1.id == target_id)) do
      nil -> "unknown"
      node -> truncate_text(node.title, 20)
    end
  end

  defp format_pulse(nil), do: ""

  defp format_pulse(pulse) do
    goals = length(pulse.active_goals || [])
    decisions = length(pulse.recent_decisions || [])
    gaps = length(pulse.coverage_gaps || [])

    "#{goals} active goals, #{decisions} recent decisions, #{gaps} coverage gaps"
  end

  defp load_graph_data(nil, nil, _socket), do: {[], [], nil}

  defp load_graph_data(session_id, team_id, socket) do
    try do
      session_nodes =
        if is_binary(session_id) do
          Graph.list_nodes(session_id: session_id)
        else
          []
        end

      team_nodes =
        if is_binary(team_id) do
          Graph.list_nodes(team_id: team_id)
        else
          []
        end

      nodes = Enum.uniq_by(session_nodes ++ team_nodes, & &1.id)
      node_ids = Enum.map(nodes, & &1.id)
      edges = Graph.list_edges(node_ids: node_ids)
      pulse = maybe_generate_pulse(socket)
      {nodes, edges, pulse}
    rescue
      _e ->
        {[], [], nil}
    end
  end

  defp maybe_generate_pulse(socket) do
    cached = socket.assigns[:pulse_data]
    generated_at = socket.assigns[:pulse_generated_at]
    now = System.monotonic_time(:second)

    if is_nil(cached) or is_nil(generated_at) or now - generated_at >= @pulse_ttl_seconds do
      Pulse.generate()
    else
      cached
    end
  end
end
