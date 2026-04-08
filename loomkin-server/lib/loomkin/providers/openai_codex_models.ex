defmodule Loomkin.Providers.OpenAICodexModels do
  @moduledoc false

  @fallback_entries [
    %{
      "slug" => "gpt-5.4",
      "display_name" => "gpt-5.4",
      "visibility" => "list",
      "supported_in_api" => true,
      "context_window" => 272_000,
      "input_modalities" => ["text", "image"],
      "supports_reasoning_summaries" => true
    },
    %{
      "slug" => "gpt-5.4-mini",
      "display_name" => "GPT-5.4-Mini",
      "visibility" => "list",
      "supported_in_api" => true,
      "context_window" => 272_000,
      "input_modalities" => ["text", "image"],
      "supports_reasoning_summaries" => true
    },
    %{
      "slug" => "gpt-5.3-codex",
      "display_name" => "gpt-5.3-codex",
      "visibility" => "list",
      "supported_in_api" => true,
      "context_window" => 272_000,
      "input_modalities" => ["text", "image"],
      "supports_reasoning_summaries" => true
    },
    %{
      "slug" => "gpt-5.2",
      "display_name" => "gpt-5.2",
      "visibility" => "list",
      "supported_in_api" => true,
      "context_window" => 272_000,
      "input_modalities" => ["text", "image"],
      "supports_reasoning_summaries" => true
    }
  ]

  @spec list_models() :: [LLMDB.Model.t()]
  def list_models do
    all_entries()
    |> Enum.filter(&picker_visible?/1)
    |> Enum.map(&build_model/1)
  end

  @spec resolve_model(String.t()) :: {:ok, LLMDB.Model.t()} | {:error, :not_found}
  def resolve_model(model_spec) when is_binary(model_spec) do
    model_id = canonical_model_id(model_spec)

    case Enum.find(all_entries(), &(entry_slug(&1) == model_id)) do
      nil ->
        {:error, :not_found}

      entry ->
        if supported_in_api?(entry) do
          {:ok, build_model(entry)}
        else
          {:error, :not_found}
        end
    end
  end

  defp all_entries do
    cache_entries = load_cache_entries()
    cache_ids = MapSet.new(cache_entries, &entry_slug/1)

    cache_entries ++
      Enum.reject(@fallback_entries, fn entry ->
        MapSet.member?(cache_ids, entry_slug(entry))
      end)
  end

  defp load_cache_entries do
    case File.read(cache_path()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"models" => models}} when is_list(models) ->
            Enum.filter(models, &is_binary(entry_slug(&1)))

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp cache_path do
    Application.get_env(:loomkin, __MODULE__, [])
    |> Keyword.get(:cache_path, Path.join(codex_home(), "models_cache.json"))
  end

  defp codex_home do
    System.get_env("CODEX_HOME") || Path.join(System.user_home!(), ".codex")
  end

  defp build_model(entry) do
    model_id = entry_slug(entry)

    LLMDB.Model.new!(%{
      id: model_id,
      provider: :openai,
      provider_model_id: model_id,
      name: entry_display_name(entry),
      limits: %{
        context: entry_context_window(entry),
        output: nil
      },
      capabilities: %{
        chat: true,
        reasoning: %{enabled: reasoning_enabled?(entry)},
        tools: %{enabled: true, streaming: true, strict: true, parallel: true},
        json: %{native: true, schema: true, strict: true},
        streaming: %{text: true, tool_calls: true}
      },
      modalities: %{
        input: input_modalities(entry),
        output: [:text]
      },
      deprecated: false,
      retired: false,
      extra: %{
        wire: %{protocol: "openai_responses"},
        loomkin: %{source: "codex_models_cache"},
        codex: %{
          visibility: visibility(entry),
          supported_in_api: supported_in_api?(entry)
        }
      }
    })
  end

  defp canonical_model_id(model_spec) do
    model_spec
    |> String.replace_prefix("openai_oauth:", "")
    |> String.replace_prefix("openai:", "")
  end

  defp entry_slug(entry), do: fetch_string(entry, "slug") || fetch_string(entry, "id")

  defp entry_display_name(entry), do: fetch_string(entry, "display_name") || entry_slug(entry)

  defp entry_context_window(entry) do
    case fetch_value(entry, "context_window") do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  defp picker_visible?(entry), do: supported_in_api?(entry) and visibility(entry) == "list"

  defp visibility(entry), do: fetch_string(entry, "visibility") || "list"

  defp supported_in_api?(entry) do
    case fetch_value(entry, "supported_in_api") do
      false -> false
      _ -> true
    end
  end

  defp reasoning_enabled?(entry) do
    case fetch_value(entry, "supports_reasoning_summaries") do
      false -> false
      _ -> true
    end
  end

  defp input_modalities(entry) do
    entry
    |> fetch_value("input_modalities")
    |> List.wrap()
    |> Enum.flat_map(&normalize_modality/1)
    |> case do
      [] -> [:text]
      modalities -> Enum.uniq(modalities)
    end
  end

  defp normalize_modality("text"), do: [:text]
  defp normalize_modality("image"), do: [:image]
  defp normalize_modality("audio"), do: [:audio]
  defp normalize_modality(:text), do: [:text]
  defp normalize_modality(:image), do: [:image]
  defp normalize_modality(:audio), do: [:audio]
  defp normalize_modality(_), do: []

  defp fetch_string(entry, key) do
    case fetch_value(entry, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch_value(entry, key) when is_map(entry) do
    case Map.fetch(entry, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(entry, String.to_atom(key))
    end
  rescue
    ArgumentError -> Map.get(entry, key)
  end
end
