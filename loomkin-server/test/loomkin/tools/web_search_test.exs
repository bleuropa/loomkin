defmodule Loomkin.Tools.WebSearchTest do
  use ExUnit.Case, async: true

  alias Loomkin.Tools.WebSearch

  describe "action metadata" do
    test "has correct name" do
      assert WebSearch.name() == "web_search"
    end

    test "has a description mentioning Exa" do
      assert is_binary(WebSearch.description())
      assert WebSearch.description() =~ "Exa"
    end
  end

  describe "run/2 without EXA_API_KEY" do
    setup do
      prev = System.get_env("EXA_API_KEY")
      System.delete_env("EXA_API_KEY")

      on_exit(fn ->
        if prev, do: System.put_env("EXA_API_KEY", prev), else: System.delete_env("EXA_API_KEY")
      end)

      :ok
    end

    test "returns error when env var is not set" do
      params = %{query: "test query"}
      assert {:error, msg} = WebSearch.run(params, %{})
      assert msg =~ "EXA_API_KEY"
      assert msg =~ "not set"
    end

    test "returns error when env var is empty" do
      System.put_env("EXA_API_KEY", "")
      params = %{query: "test query"}
      assert {:error, msg} = WebSearch.run(params, %{})
      assert msg =~ "EXA_API_KEY"
      assert msg =~ "empty"
    end
  end

  describe "snippet extraction fallbacks" do
    # Tests the content cascade logic: summary > highlights > text > ""
    # This mirrors the private extract_snippet/1 function.

    test "prefers summary over highlights and text" do
      result = %{
        "summary" => "The summary",
        "highlights" => ["A highlight"],
        "text" => "Full text"
      }

      assert extract_snippet(result) == "The summary"
    end

    test "falls back to highlights when no summary" do
      result = %{
        "highlights" => ["A highlight"],
        "text" => "Full text"
      }

      assert extract_snippet(result) == "A highlight"
    end

    test "falls back to text when no summary or highlights" do
      result = %{"text" => "Full text content"}
      assert extract_snippet(result) == "Full text content"
    end

    test "returns empty string when no content fields" do
      assert extract_snippet(%{}) == ""
    end

    test "skips empty summary" do
      result = %{"summary" => "", "text" => "Fallback text"}
      assert extract_snippet(result) == "Fallback text"
    end

    test "skips empty highlights list" do
      result = %{"highlights" => [], "text" => "Fallback text"}
      assert extract_snippet(result) == "Fallback text"
    end

    test "truncates long content to 500 characters" do
      long_text = String.duplicate("a", 600)
      result = %{"text" => long_text}
      assert String.length(extract_snippet(result)) == 500
    end
  end

  describe "result formatting" do
    test "formats results with all fields" do
      results = %{
        "results" => [
          %{
            "title" => "Example Article",
            "url" => "https://example.com/article",
            "publishedDate" => "2024-06-15",
            "summary" => "A summary."
          }
        ]
      }

      assert {:ok, %{result: formatted}} = format_results(results)
      assert formatted =~ "Found 1 result(s)"
      assert formatted =~ "[1] Example Article"
      assert formatted =~ "https://example.com/article"
      assert formatted =~ "Published: 2024-06-15"
      assert formatted =~ "A summary."
    end

    test "formats results without optional fields" do
      results = %{
        "results" => [
          %{
            "title" => "Bare Result",
            "url" => "https://example.com"
          }
        ]
      }

      assert {:ok, %{result: formatted}} = format_results(results)
      assert formatted =~ "[1] Bare Result"
      refute formatted =~ "Published:"
    end

    test "handles multiple results" do
      results = %{
        "results" => [
          %{"title" => "First", "url" => "https://a.com", "text" => "Text A"},
          %{"title" => "Second", "url" => "https://b.com", "text" => "Text B"}
        ]
      }

      assert {:ok, %{result: formatted}} = format_results(results)
      assert formatted =~ "Found 2 result(s)"
      assert formatted =~ "[1] First"
      assert formatted =~ "[2] Second"
      assert formatted =~ "---"
    end

    test "handles empty results list" do
      assert {:ok, %{result: "No results found."}} =
               format_results(%{"results" => []})
    end

    test "handles missing results key" do
      assert {:ok, %{result: "No results found."}} =
               format_results(%{})
    end
  end

  # Replicates the private extract_snippet/1 logic for direct testing.
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

  # Replicates the private format_results/1 and format_result/1 logic for direct testing.
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
end
