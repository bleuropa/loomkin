defmodule LoomkinWeb.VaultEntryLive do
  @moduledoc "Vault entry viewer — renders a single vault entry with markdown, frontmatter, and backlinks."

  use LoomkinWeb, :live_view

  alias Loomkin.Vault
  alias Loomkin.Vault.Index

  @wiki_link_regex ~r/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/

  @impl true
  def mount(%{"slug" => slug, "path" => path_parts}, _session, socket) do
    path = Enum.join(path_parts, "/")
    vault = Vault.get_vault_by_slug!(slug)
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    if Vault.user_can_access_vault?(user, vault) do
      case Vault.read(slug, path) do
        {:ok, entry} ->
          backlinks = Index.backlinks(slug, path)
          rendered_html = render_vault_markdown(entry.body, slug)
          headings = extract_headings(entry.body)

          {:ok,
           assign(socket,
             vault: vault,
             slug: slug,
             path: path,
             entry: entry,
             backlinks: backlinks,
             rendered_html: rendered_html,
             headings: headings,
             page_title: entry.title || Path.basename(path, ".md")
           )}

        {:error, :not_found} ->
          {:ok,
           socket
           |> put_flash(:error, "Entry not found: #{path}")
           |> redirect(to: ~p"/vault/#{slug}")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have access to this vault.")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen" style="background: var(--surface-0);">
      <%!-- Top bar with breadcrumb --%>
      <header
        class="sticky top-0 z-30 flex items-center gap-3 px-6 py-3 border-b"
        style="background: var(--surface-1); border-color: var(--border-default);"
      >
        <.link
          navigate={~p"/vault/#{@slug}"}
          class="flex items-center gap-1.5 text-sm transition-colors hover:text-[var(--brand)]"
          style="color: var(--text-secondary);"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-4 h-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          {@vault.name}
        </.link>

        <span style="color: var(--text-muted);">/</span>

        <span
          :if={@entry.entry_type}
          class="text-xs font-medium uppercase tracking-wider px-1.5 py-0.5 rounded"
          style="background: var(--surface-2); color: var(--text-muted);"
        >
          {@entry.entry_type}
        </span>

        <span class="text-sm truncate" style="color: var(--text-primary);">
          {@entry.title || Path.basename(@path, ".md")}
        </span>
      </header>

      <%!-- Content area — 2-column: article + sidebar --%>
      <div class="max-w-6xl mx-auto px-6 py-8 md:py-12 flex gap-10">
        <%!-- Main column --%>
        <div class="min-w-0 flex-1 max-w-3xl">
          <%!-- Entry header --%>
          <div class="mb-8">
            <h1
              class="text-2xl md:text-3xl font-semibold leading-tight mb-2"
              style="color: var(--text-primary);"
            >
              {@entry.title || Path.basename(@path, ".md")}
            </h1>
            <div class="flex items-center gap-2 mt-2">
              <span
                :if={@entry.entry_type}
                class="text-xs font-medium uppercase tracking-wider px-2 py-1 rounded-md"
                style="background: var(--brand-subtle); color: var(--text-brand);"
              >
                {@entry.entry_type}
              </span>
              <span :if={meta_date(@entry)} class="text-xs" style="color: var(--text-muted);">
                {meta_date(@entry)}
              </span>
              <span :if={meta_author(@entry)} class="text-xs" style="color: var(--text-muted);">
                by {meta_author(@entry)}
              </span>
            </div>
          </div>

          <%!-- Rendered markdown body --%>
          <article class="vault-prose" id="vault-entry-body">
            {raw(@rendered_html)}
          </article>

          <%!-- Backlinks --%>
          <div
            :if={@backlinks != []}
            class="mt-12 pt-8 border-t"
            style="border-color: var(--border-subtle);"
          >
            <h2
              class="flex items-center gap-2 text-xs font-medium uppercase tracking-wider mb-4"
              style="color: var(--text-muted);"
            >
              Linked from ({length(@backlinks)})
            </h2>
            <div class="space-y-1">
              <.link
                :for={bl <- @backlinks}
                navigate={~p"/vault/#{@slug}/#{bl.path}"}
                class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors hover:bg-[var(--surface-1)]"
                style="color: var(--text-secondary);"
              >
                <span
                  class="text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded"
                  style="background: var(--surface-2); color: var(--text-muted);"
                >
                  {bl.link_type}
                </span>
                <span class="hover:text-[var(--brand)]">
                  {bl.title || Path.basename(bl.path, ".md")}
                </span>
              </.link>
            </div>
          </div>
        </div>

        <%!-- Sidebar — metadata + TOC --%>
        <aside class="hidden lg:block w-56 shrink-0 sticky top-20 self-start space-y-6">
          <%!-- Metadata --%>
          <div
            class="rounded-lg p-4 space-y-3"
            style="background: var(--surface-1); border: 1px solid var(--border-subtle);"
          >
            <div :if={meta_val(@entry, "status")} class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                Status
              </span>
              <span
                class="inline-block px-2 py-0.5 rounded text-xs font-medium"
                style={"background: #{status_color(meta_val(@entry, "status"))}; color: var(--surface-0);"}
              >
                {meta_val(@entry, "status")}
              </span>
            </div>
            <div :if={meta_date(@entry)} class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                Date
              </span>
              <span style="color: var(--text-secondary);">{meta_date(@entry)}</span>
            </div>
            <div :if={meta_author(@entry)} class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                Author
              </span>
              <span style="color: var(--text-secondary);">{meta_author(@entry)}</span>
            </div>
            <div :if={meta_val(@entry, "id")} class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                ID
              </span>
              <span class="font-mono" style="color: var(--text-secondary);">
                {meta_val(@entry, "id")}
              </span>
            </div>
            <div :if={(@entry.tags || []) != []} class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                Tags
              </span>
              <div class="flex flex-wrap gap-1">
                <span
                  :for={tag <- @entry.tags}
                  class="px-1.5 py-0.5 rounded"
                  style="background: var(--brand-muted); color: var(--text-brand);"
                >
                  {tag}
                </span>
              </div>
            </div>
            <div class="text-xs">
              <span
                class="block font-medium uppercase tracking-wider mb-1"
                style="color: var(--text-muted);"
              >
                Path
              </span>
              <span class="font-mono break-all" style="color: var(--text-muted);">{@path}</span>
            </div>
          </div>

          <%!-- Table of Contents --%>
          <div :if={@headings != []} class="space-y-1">
            <p
              class="text-xs font-medium uppercase tracking-wider mb-2 px-1"
              style="color: var(--text-muted);"
            >
              On this page
            </p>
            <a
              :for={%{level: level, text: text, anchor: anchor} <- @headings}
              href={"##{anchor}"}
              class="block text-xs py-1 transition-colors hover:text-[var(--brand)]"
              style={"color: var(--text-muted); padding-left: #{(level - 1) * 0.75}rem;"}
            >
              {text}
            </a>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  # --- Markdown rendering ---

  defp render_vault_markdown(nil, _slug), do: ""

  defp render_vault_markdown(body, slug) do
    body
    |> convert_wiki_links(slug)
    |> MDEx.to_html!(
      extension: [table: true, strikethrough: true, tasklist: true, autolink: true]
    )
    |> add_heading_ids()
  end

  @heading_tag_regex ~r/<(h[1-4])>(.+?)<\/h[1-4]>/

  defp add_heading_ids(html) do
    Regex.replace(@heading_tag_regex, html, fn _, tag, text ->
      plain = String.replace(text, ~r/<[^>]+>/, "")
      anchor = slugify_heading(plain)
      ~s(<#{tag} id="#{anchor}">#{text}</#{tag}>)
    end)
  end

  defp convert_wiki_links(body, slug) do
    Regex.replace(@wiki_link_regex, body, fn _, path, display ->
      display = if display == "", do: Path.basename(path, ".md"), else: display

      ~s(<a href="/vault/#{slug}/#{path}" class="vault-wiki-link">#{Phoenix.HTML.html_escape(display) |> Phoenix.HTML.safe_to_string()}</a>)
    end)
  end

  # --- Metadata helpers ---

  defp meta_date(%{metadata: %{"date" => date}}) when is_binary(date), do: date
  defp meta_date(_), do: nil

  defp meta_author(%{metadata: %{"author" => author}}) when is_binary(author), do: author
  defp meta_author(_), do: nil

  defp meta_val(%{metadata: meta}, key) when is_map(meta) do
    case Map.get(meta, key) do
      val when is_binary(val) and val != "" -> val
      _ -> nil
    end
  end

  defp meta_val(_, _), do: nil

  defp status_color("draft"), do: "var(--accent-amber)"
  defp status_color("published"), do: "var(--accent-emerald)"
  defp status_color("approved"), do: "var(--accent-emerald)"
  defp status_color("implemented"), do: "var(--accent-cyan)"
  defp status_color("planned"), do: "var(--accent-amber)"
  defp status_color("in-progress"), do: "var(--accent-peach)"
  defp status_color("done"), do: "var(--accent-emerald)"
  defp status_color("archived"), do: "var(--text-muted)"
  defp status_color("accepted"), do: "var(--accent-emerald)"
  defp status_color("rejected"), do: "var(--accent-rose)"
  defp status_color(_), do: "var(--surface-3)"

  # --- Heading extraction for TOC ---

  @heading_regex ~r/^(\#{1,4})\s+(.+)$/m

  defp extract_headings(nil), do: []

  defp extract_headings(body) do
    Regex.scan(@heading_regex, body)
    |> Enum.map(fn [_, hashes, text] ->
      %{
        level: String.length(hashes),
        text: text |> String.trim(),
        anchor: text |> String.trim() |> slugify_heading()
      }
    end)
  end

  defp slugify_heading(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s]+/, "-")
    |> String.trim("-")
  end
end
