defmodule LoomkinWeb.HomeLive do
  @moduledoc """
  Landing page. In local mode, redirects to the project picker.
  In multi-tenant mode, shows the user's accessible vaults.
  """
  use LoomkinWeb, :live_view

  alias Loomkin.Vault

  def mount(_params, _session, socket) do
    unless Application.get_env(:loomkin, :multi_tenant) do
      {:ok, push_navigate(socket, to: ~p"/projects")}
    else
      user = socket.assigns.current_scope && socket.assigns.current_scope.user

      vaults =
        if user do
          load_user_vaults(user)
        else
          []
        end

      {:ok,
       assign(socket,
         page_title: "Loomkin",
         user: user,
         vaults: vaults
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen" style="background: var(--surface-0);">
      <div class="home-aurora" aria-hidden="true" />

      <%!-- Top nav --%>
      <nav
        class="sticky top-0 z-30 border-b bg-surface-0/90 backdrop-blur-xl"
        style="border-color: var(--border-subtle);"
      >
        <div class="max-w-5xl mx-auto px-5">
          <div class="flex items-center justify-between h-12">
            <.link navigate={~p"/"} class="flex items-center gap-2 group">
              <svg
                width="24"
                height="24"
                viewBox="0 0 52 52"
                fill="none"
                class="opacity-80 group-hover:opacity-100 transition-opacity"
              >
                <ellipse
                  cx="26"
                  cy="26"
                  rx="18"
                  ry="8"
                  transform="rotate(-30 26 26)"
                  stroke="#7C3AED"
                  stroke-width="2.5"
                  fill="none"
                />
                <ellipse
                  cx="26"
                  cy="26"
                  rx="18"
                  ry="8"
                  transform="rotate(30 26 26)"
                  stroke="#22d3ee"
                  stroke-width="2.5"
                  fill="none"
                  opacity="0.6"
                />
                <ellipse
                  cx="26"
                  cy="26"
                  rx="18"
                  ry="8"
                  transform="rotate(90 26 26)"
                  stroke="#a78bfa"
                  stroke-width="2.5"
                  fill="none"
                  opacity="0.5"
                />
              </svg>
              <span
                class="text-sm font-light tracking-wide hidden sm:inline"
                style="color: var(--text-secondary);"
              >
                loom<span class="font-semibold" style="color: var(--brand);">kin</span>
              </span>
            </.link>

            <div class="flex items-center gap-3">
              <%= if @user do %>
                <.link
                  navigate={~p"/users/settings"}
                  class="w-7 h-7 rounded-full flex items-center justify-center transition-all"
                  style="background: var(--surface-3); border: 1px solid var(--border-subtle);"
                >
                  <span class="text-[10px] font-bold" style="color: var(--text-muted);">
                    {((@user.username || @user.email || "?") |> String.first() || "?")
                    |> String.upcase()}
                  </span>
                </.link>
              <% else %>
                <.link
                  href={~p"/users/log-in"}
                  class="px-3 py-1 rounded-md text-xs transition-colors"
                  style="color: var(--text-muted);"
                >
                  Log in
                </.link>
                <.link
                  href={~p"/users/register"}
                  class="px-3 py-1 rounded-md text-xs font-medium text-white transition-colors"
                  style="background: var(--brand);"
                >
                  Sign up
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </nav>

      <%!-- Main content --%>
      <div class="relative z-10 max-w-5xl mx-auto px-5">
        <%= if @user do %>
          <.vault_dashboard user={@user} vaults={@vaults} />
        <% else %>
          <.signed_out_hero />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Signed-out hero ──

  defp signed_out_hero(assigns) do
    ~H"""
    <div class="pt-24 pb-20 text-center">
      <div class="inline-block mb-6">
        <svg
          width="64"
          height="64"
          viewBox="0 0 52 52"
          fill="none"
          class="drop-shadow-[0_0_20px_rgba(124,58,237,0.25)]"
        >
          <ellipse
            cx="26"
            cy="26"
            rx="18"
            ry="8"
            transform="rotate(-30 26 26)"
            stroke="url(#eh1)"
            stroke-width="1.5"
            fill="none"
          />
          <ellipse
            cx="26"
            cy="26"
            rx="18"
            ry="8"
            transform="rotate(30 26 26)"
            stroke="url(#eh2)"
            stroke-width="1.5"
            fill="none"
          />
          <ellipse
            cx="26"
            cy="26"
            rx="18"
            ry="8"
            transform="rotate(90 26 26)"
            stroke="url(#eh3)"
            stroke-width="1.5"
            fill="none"
          />
          <defs>
            <linearGradient id="eh1" x1="8" y1="18" x2="44" y2="34" gradientUnits="userSpaceOnUse">
              <stop stop-color="#7C3AED" />
              <stop offset="1" stop-color="#a78bfa" />
            </linearGradient>
            <linearGradient id="eh2" x1="8" y1="34" x2="44" y2="18" gradientUnits="userSpaceOnUse">
              <stop stop-color="#22d3ee" stop-opacity="0.6" />
              <stop offset="1" stop-color="#7C3AED" />
            </linearGradient>
            <linearGradient id="eh3" x1="26" y1="8" x2="26" y2="44" gradientUnits="userSpaceOnUse">
              <stop stop-color="#a78bfa" stop-opacity="0.5" />
              <stop offset="1" stop-color="#22d3ee" stop-opacity="0.7" />
            </linearGradient>
          </defs>
        </svg>
      </div>
      <h1 class="text-3xl font-light tracking-tight mb-3" style="color: var(--text-primary);">
        Welcome to <span class="font-semibold">Loomkin</span>
      </h1>
      <p class="text-sm max-w-md mx-auto leading-relaxed mb-8" style="color: var(--text-muted);">
        AI-powered team knowledge base. Your agents organize meeting notes, decisions, and documentation — you browse the results.
      </p>
      <.link
        href={~p"/users/log-in"}
        class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg text-sm font-medium text-white transition-all"
        style="background: var(--brand);"
      >
        Log in to continue
      </.link>
    </div>
    """
  end

  # ── Vault dashboard (signed in) ──

  attr :user, :any, required: true
  attr :vaults, :list, required: true

  defp vault_dashboard(assigns) do
    ~H"""
    <div class="pt-12 pb-20">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-xl font-semibold mb-1" style="color: var(--text-primary);">
            Your Vaults
          </h1>
          <p class="text-sm" style="color: var(--text-muted);">
            Knowledge bases managed by your teams
          </p>
        </div>
      </div>

      <%= if @vaults == [] do %>
        <div
          class="rounded-xl p-12 text-center border"
          style="background: var(--surface-1); border-color: var(--border-subtle);"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-10 h-10 mx-auto mb-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="1"
            style="color: var(--text-muted);"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
            />
          </svg>
          <p class="text-sm mb-1" style="color: var(--text-secondary);">
            No vaults available yet
          </p>
          <p class="text-xs" style="color: var(--text-muted);">
            Vaults will appear here once your organization sets one up.
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <.vault_card :for={vault <- @vaults} vault={vault} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :vault, :map, required: true

  defp vault_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/vault/#{@vault.vault_id}"}
      class="group block rounded-xl p-5 border transition-all"
      style="background: var(--surface-1); border-color: var(--border-subtle);"
    >
      <div class="flex items-start gap-3 mb-3">
        <div
          class="w-9 h-9 rounded-lg flex items-center justify-center shrink-0"
          style="background: var(--brand-subtle);"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-4.5 h-4.5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="1.5"
            style="color: var(--brand);"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
            />
          </svg>
        </div>
        <div class="min-w-0">
          <h3
            class="text-sm font-medium truncate group-hover:text-[var(--brand)]"
            style="color: var(--text-primary); transition: color var(--transition-fast);"
          >
            {@vault.name}
          </h3>
          <p
            :if={@vault.description}
            class="text-xs mt-0.5 line-clamp-2"
            style="color: var(--text-muted);"
          >
            {@vault.description}
          </p>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <span
          class="text-xs px-2 py-0.5 rounded"
          style="background: var(--surface-2); color: var(--text-muted);"
        >
          {@vault.storage_type}
        </span>
        <span
          class="text-xs ml-auto opacity-0 group-hover:opacity-100 transition-opacity"
          style="color: var(--text-brand);"
        >
          Open →
        </span>
      </div>
    </.link>
    """
  end

  # ── Data loading ──

  defp load_user_vaults(user) do
    import Ecto.Query

    # Get all orgs the user belongs to
    org_ids =
      Loomkin.Repo.all(
        from(m in Loomkin.Schemas.OrganizationMembership,
          where: m.user_id == ^user.id,
          select: m.organization_id
        )
      )

    # Get vaults for those orgs + unscoped vaults
    Loomkin.Repo.all(
      from(vc in Loomkin.Schemas.VaultConfig,
        where: vc.organization_id in ^org_ids or is_nil(vc.organization_id),
        order_by: [asc: vc.name]
      )
    )
  end
end
