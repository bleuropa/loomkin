defmodule Loomkin.Tools.WebSearch do
  @moduledoc "Searches the web using the Exa AI search API."

  use Jido.Action,
    name: "web_search",
    description:
      "Search the web using Exa AI. Returns relevant web pages with titles, URLs, " <>
        "and content snippets. Useful for finding documentation, research, articles, " <>
        "and real-time information from the internet. " <>
        "Requires EXA_API_KEY environment variable.",
    schema: [
      query: [type: :string, required: true, doc: "Search query"],
      type: [
        type: :string,
        doc: "Search type: auto (default), neural, or fast"
      ],
      num_results: [
        type: :integer,
        doc: "Number of results to return (1-20, default: 5)"
      ],
      category: [
        type: :string,
        doc:
          "Filter by category: company, research paper, news, " <>
            "personal site, financial report, people"
      ],
      include_domains: [
        type: {:list, :string},
        doc: "Only include results from these domains"
      ],
      exclude_domains: [
        type: {:list, :string},
        doc: "Exclude results from these domains"
      ],
      include_text: [
        type: :string,
        doc: "Only return results containing this text"
      ],
      exclude_text: [
        type: :string,
        doc: "Exclude results containing this text"
      ],
      start_published_date: [
        type: :string,
        doc: "Only results published after this date (ISO 8601, e.g. 2024-01-01T00:00:00Z)"
      ],
      end_published_date: [
        type: :string,
        doc: "Only results published before this date (ISO 8601, e.g. 2024-12-31T23:59:59Z)"
      ]
    ]

  import Loomkin.Tool, only: [param!: 2, param: 2]

  @api_url "https://api.exa.ai/search"

  @impl true
  def run(params, _context) do
    case System.get_env("EXA_API_KEY") do
      nil -> {:error, "EXA_API_KEY environment variable is not set"}
      "" -> {:error, "EXA_API_KEY environment variable is empty"}
      api_key -> do_search(params, api_key)
    end
  end

  defp do_search(params, api_key) do
    query = param!(params, :query)
    num_results = min(max(param(params, :num_results) || 5, 1), 20)

    body =
      %{
        query: query,
        numResults: num_results,
        contents: %{
          text: %{maxCharacters: 1000},
          highlights: true,
          summary: %{query: query}
        }
      }
      |> put_optional(:type, param(params, :type))
      |> put_optional(:category, param(params, :category))
      |> put_optional(:includeDomains, param(params, :include_domains))
      |> put_optional(:excludeDomains, param(params, :exclude_domains))
      |> put_optional_wrapped(:includeText, param(params, :include_text))
      |> put_optional_wrapped(:excludeText, param(params, :exclude_text))
      |> put_optional(:startPublishedDate, param(params, :start_published_date))
      |> put_optional(:endPublishedDate, param(params, :end_published_date))

    headers = [
      {"x-api-key", api_key},
      {"content-type", "application/json"},
      {"x-exa-integration", "loomkin"}
    ]

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        format_results(resp_body)

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Exa API authentication failed. Check your EXA_API_KEY."}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "Exa API rate limit exceeded. Try again later."}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        msg = if is_map(body), do: Map.get(body, "error", "Unknown error"), else: "HTTP #{status}"
        {:error, "Exa API error (#{status}): #{msg}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "Exa API request timed out"}

      {:error, reason} ->
        {:error, "Exa API request failed: #{inspect(reason)}"}
    end
  end

  defp format_results(%{"results" => results}) when is_list(results) and results != [] do
    formatted =
      results
      |> Enum.with_index(1)
      |> Enum.map(&format_result/1)
      |> Enum.join("\n\n---\n\n")

    {:ok, %{result: "Found #{length(results)} result(s):\n\n#{formatted}"}}
  end

  defp format_results(_), do: {:ok, %{result: "No results found."}}

  defp format_result({result, index}) do
    title = Map.get(result, "title", "Untitled")
    url = Map.get(result, "url", "")
    published = Map.get(result, "publishedDate")
    snippet = extract_snippet(result)

    lines = ["[#{index}] #{title}", "    #{url}"]
    lines = if published, do: lines ++ ["    Published: #{published}"], else: lines
    lines = if snippet != "", do: lines ++ ["    #{snippet}"], else: lines

    Enum.join(lines, "\n")
  end

  defp extract_snippet(result) do
    summary = Map.get(result, "summary")
    highlights = Map.get(result, "highlights", [])
    text = Map.get(result, "text")

    cond do
      is_binary(summary) and summary != "" ->
        String.slice(summary, 0, 500)

      is_list(highlights) and highlights != [] ->
        highlights |> hd() |> String.slice(0, 500)

      is_binary(text) and text != "" ->
        String.slice(text, 0, 500)

      true ->
        ""
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp put_optional_wrapped(map, _key, nil), do: map
  defp put_optional_wrapped(map, key, value), do: Map.put(map, key, [value])
end
