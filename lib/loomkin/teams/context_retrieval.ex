defmodule Loomkin.Teams.ContextRetrieval do
  @moduledoc "How agents find and retrieve context from keepers."

  alias Loomkin.Teams.ContextKeeper

  @default_max_tokens 8000

  @doc """
  List all keepers for a team.

  Returns a list of maps: `[%{id: id, topic: topic, source_agent: source_agent, token_count: count}]`
  """
  def list_keepers(team_id) do
    Registry.select(Loomkin.Teams.AgentRegistry, [
      {{{team_id, :"$1"}, :"$2", :"$3"}, [], [%{name: :"$1", pid: :"$2", meta: :"$3"}]}
    ])
    |> Enum.filter(fn %{meta: meta} -> meta[:type] == :keeper end)
    |> Enum.map(fn %{name: name, pid: pid, meta: meta} ->
      # name is "keeper:<id>"
      id = String.replace_prefix(to_string(name), "keeper:", "")

      %{
        id: id,
        pid: pid,
        topic: meta[:topic] || "unnamed",
        source_agent: meta[:source_agent] || "unknown",
        token_count: meta[:tokens] || 0
      }
    end)
  end

  @doc """
  Search keepers by relevance to a query.

  Scores keepers by topic similarity and returns sorted results.
  """
  def search(team_id, query) do
    query_words =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> MapSet.new()

    list_keepers(team_id)
    |> Enum.map(fn keeper ->
      topic_words =
        keeper.topic
        |> String.downcase()
        |> String.split(~r/\s+/, trim: true)
        |> MapSet.new()

      relevance = MapSet.intersection(query_words, topic_words) |> MapSet.size()

      Map.put(keeper, :relevance, relevance)
    end)
    |> Enum.sort_by(& &1.relevance, :desc)
  end

  @doc """
  Retrieve context from a specific keeper or search all.

  Options:
    - `:keeper_id` - retrieve from a specific keeper
    - `:max_tokens` - maximum tokens to return (default 8000)
    - `:mode` - `:smart` for LLM-summarized answers, `:raw` for raw messages.
      When omitted, auto-detected from query (questions → :smart, keywords → :raw).

  Returns `{:ok, messages}` or `{:error, :not_found}`.
  """
  def retrieve(team_id, query, opts \\ []) do
    keeper_id = Keyword.get(opts, :keeper_id)
    _max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    mode = Keyword.get(opts, :mode, detect_mode(query))

    if keeper_id do
      retrieve_from_keeper(team_id, keeper_id, query, mode)
    else
      retrieve_from_best(team_id, query, mode)
    end
  end

  @doc "Smart retrieval — asks keepers a question and gets a focused answer."
  def smart_retrieve(team_id, question, opts \\ []) do
    retrieve(team_id, question, Keyword.put(opts, :mode, :smart))
  end

  @max_synthesis_chars 32_000
  @max_keepers 5

  @doc """
  Synthesize context from multiple keepers into a unified answer.

  Searches keepers by relevance, retrieves raw content from the top matches,
  and sends the combined context to an LLM for synthesis.

  Returns `{:ok, answer}` or `{:error, :not_found}`.
  """
  def synthesize(team_id, question) do
    top_keepers =
      search(team_id, question)
      |> Enum.filter(&(&1.relevance > 0))
      |> Enum.take(@max_keepers)

    case top_keepers do
      [] ->
        {:error, :not_found}

      keepers ->
        sections =
          retrieve_from_multiple(keepers, question)
          |> Enum.reject(&(&1.content == ""))

        case sections do
          [] -> {:error, :not_found}
          _ -> synthesize_with_llm(sections, question)
        end
    end
  end

  # --- Private ---

  defp retrieve_from_multiple(keepers, query) do
    keepers
    |> Enum.reduce_while({[], 0}, fn keeper, {acc, chars_used} ->
      if chars_used >= @max_synthesis_chars do
        {:halt, {acc, chars_used}}
      else
        budget = @max_synthesis_chars - chars_used

        content =
          case ContextKeeper.retrieve(keeper.pid, query) do
            {:ok, messages} when is_list(messages) -> format_messages(messages)
            {:ok, text} when is_binary(text) -> text
            _ -> ""
          end

        trimmed = String.slice(content, 0, budget)
        section = %{topic: keeper.topic, source: keeper.source_agent, content: trimmed}
        {:cont, {[section | acc], chars_used + String.length(trimmed)}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", fn msg ->
      role = msg[:role] || msg["role"] || "unknown"
      content = msg[:content] || msg["content"] || ""
      "[#{role}]: #{content}"
    end)
  end

  defp synthesize_with_llm(sections, question) do
    model = Loomkin.Teams.ModelRouter.default_model()

    keeper_context =
      sections
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {section, i} ->
        "--- Keeper #{i} (#{section.topic}, from #{section.source}) ---\n#{section.content}"
      end)

    messages = [
      ReqLLM.Context.system("""
      You are synthesizing information from multiple context keepers. \
      Provide a unified, coherent answer to the question. Use ONLY the \
      provided context. Be specific and concise. If the context doesn't \
      fully answer the question, say what is known and what is missing.\
      """),
      ReqLLM.Context.user("Question: #{question}\n\n#{keeper_context}")
    ]

    fallback = fn ->
      Enum.map_join(sections, "\n\n", fn s -> "## #{s.topic}\n#{s.content}" end)
    end

    case call_llm(model, messages) do
      {:ok, response} ->
        case ReqLLM.Response.classify(response).text do
          text when is_binary(text) and text != "" -> {:ok, text}
          _ -> {:ok, fallback.()}
        end

      {:error, _reason} ->
        {:ok, fallback.()}
    end
  end

  defp call_llm(model, messages) do
    Loomkin.LLM.generate_text(model, messages, [])
  rescue
    e -> {:error, Exception.message(e)}
  end

  @question_starters ~w(what how why where when who which did does is are was were can could should would)

  @doc false
  def detect_mode(query) do
    downcased = String.downcase(String.trim(query))

    cond do
      String.contains?(query, "?") -> :smart
      Enum.any?(@question_starters, &String.starts_with?(downcased, &1 <> " ")) -> :smart
      true -> :raw
    end
  end

  defp retrieve_from_keeper(team_id, keeper_id, query, mode) do
    case Registry.lookup(Loomkin.Teams.AgentRegistry, {team_id, "keeper:#{keeper_id}"}) do
      [{pid, _meta}] ->
        case mode do
          :smart -> ContextKeeper.smart_retrieve(pid, query)
          :raw -> ContextKeeper.retrieve(pid, query)
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp retrieve_from_best(team_id, query, mode) do
    case search(team_id, query) |> Enum.filter(&(&1.relevance > 0)) do
      [best | _rest] ->
        case mode do
          :smart -> ContextKeeper.smart_retrieve(best.pid, query)
          :raw -> ContextKeeper.retrieve(best.pid, query)
        end

      [] ->
        {:error, :not_found}
    end
  end
end
