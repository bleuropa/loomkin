defmodule LoomkinWeb.OrchestrationTourLive do
  @moduledoc """
  Read-only rich walkthrough of the 9-phase orchestration pipeline and the
  named personas that staff each phase.

  Reached from `/orchestration/tour`. Also auto-shown in the CLI feed the
  first time a user triggers a `:complex_task` (see
  `Loomkin.Orchestration.SessionBridge`).

  Styling mirrors the rest of the orchestration LiveViews: Cozy Studio
  tokens via `assets/css/app.css`, plus the project's `.card` /
  `.loom-btn-*` utility classes.
  """

  use LoomkinWeb, :live_view

  alias Loomkin.Accounts
  alias Loomkin.Orchestration
  alias Loomkin.Orchestration.Personas

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Orchestration tour")
     |> assign(:phases, build_phase_rows())
     |> assign(:work_unit_phases, build_work_unit_rows())}
  end

  @impl true
  def handle_event("dismiss", _params, socket) do
    user = current_user(socket)

    case user && Accounts.mark_orchestration_tour_seen(user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tour dismissed. Visit this page anytime to see it again.")
         |> push_navigate(to: ~p"/orchestration")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not dismiss tour.")}
    end
  end

  defp current_user(socket) do
    case socket.assigns do
      %{current_scope: %{user: %_{} = user}} -> user
      _ -> nil
    end
  end

  defp build_phase_rows do
    Enum.map(Orchestration.phases(), fn phase ->
      persona = Personas.for_phase(phase)
      %{phase: phase, persona: persona}
    end)
  end

  defp build_work_unit_rows do
    Enum.map(Orchestration.work_unit_phases(), fn state ->
      persona = Personas.for_work_unit_state(state)
      %{state: state, persona: persona}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="min-h-screen px-6 py-10"
      style="background: var(--surface-0); color: var(--text-primary);"
      aria-labelledby="tour-h"
    >
      <div class="max-w-3xl mx-auto">
        <header class="mb-8">
          <p class="text-xs font-mono mb-2" style="color: var(--text-muted);">
            <.link navigate={~p"/orchestration"} class="hover:underline">← orchestration</.link>
          </p>
          <h1 id="tour-h" class="text-3xl font-semibold">Loomkin orchestration</h1>
          <p class="text-sm mt-2 max-w-2xl" style="color: var(--text-secondary);">
            When you ask Loomkin to do something substantial — implement a feature, fix a bug,
            refactor a module — your request runs through a 9-phase pipeline. Each phase is
            run by a named persona with one job.
          </p>
        </header>

        <section class="card p-5 mb-6" aria-labelledby="tour-phases-h">
          <h2 id="tour-phases-h" class="text-xl font-semibold mb-3">The 9 phases</h2>
          <ol class="space-y-3">
            <li
              :for={row <- @phases}
              class="flex items-start gap-3 p-3 rounded"
              style="background: var(--surface-1);"
            >
              <span class="text-2xl leading-none" aria-hidden="true">{row.persona.icon}</span>
              <div class="flex-1">
                <div class="flex items-baseline gap-2">
                  <span class="font-semibold">{row.persona.name}</span>
                  <code class="text-xs font-mono" style="color: var(--text-muted);">
                    :{row.phase}
                  </code>
                </div>
                <p class="text-sm" style="color: var(--text-secondary);">
                  {row.persona.role_blurb}
                </p>
              </div>
            </li>
          </ol>
        </section>

        <section class="card p-5 mb-6" aria-labelledby="tour-wu-h">
          <h2 id="tour-wu-h" class="text-xl font-semibold mb-3">Inside each work unit</h2>
          <p class="text-sm mb-3" style="color: var(--text-secondary);">
            The Executor runs every work unit through a 4-step inner pipeline. Validation
            runs in the orchestrator (never inside the worker that produced the code).
            Reviewers cite file:line evidence. The system retries up to 5 times with
            different settings before asking you for help.
          </p>
          <ol class="space-y-2">
            <li
              :for={row <- @work_unit_phases}
              class="flex items-center gap-3 px-3 py-2 rounded"
              style="background: var(--surface-1);"
            >
              <span class="text-xl" aria-hidden="true">{row.persona.icon}</span>
              <span class="font-semibold">{row.persona.name}</span>
              <code class="text-xs font-mono ml-auto" style="color: var(--text-muted);">
                :{row.state}
              </code>
            </li>
          </ol>
        </section>

        <section class="card p-5 mb-6" aria-labelledby="tour-control-h">
          <h2 id="tour-control-h" class="text-xl font-semibold mb-3">You stay in control</h2>
          <ul class="space-y-2 text-sm" style="color: var(--text-secondary);">
            <li>
              <kbd class="badge">p</kbd> pause an in-flight epic anytime
            </li>
            <li>
              <kbd class="badge">c</kbd> cancel and clean up the worktree
            </li>
            <li>
              <kbd class="badge">r</kbd> resume from pause
            </li>
            <li>
              Set Settings → <em>Approve at commit</em> if you want to gate every merge
            </li>
          </ul>
        </section>

        <div class="flex items-center gap-3 mt-6">
          <button
            type="button"
            phx-click="dismiss"
            class="loom-btn-primary"
            aria-label="Dismiss orchestration tour permanently"
          >
            Dismiss permanently
          </button>
          <.link navigate={~p"/orchestration"} class="loom-btn-secondary">
            Back to epics
          </.link>
        </div>
      </div>
    </main>
    """
  end
end
