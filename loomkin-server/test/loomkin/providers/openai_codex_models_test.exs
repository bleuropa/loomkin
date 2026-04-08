defmodule Loomkin.Providers.OpenAICodexModelsTest do
  use ExUnit.Case, async: false

  alias Loomkin.Providers.OpenAICodexModels

  setup do
    previous = Application.get_env(:loomkin, OpenAICodexModels)

    on_exit(fn ->
      if previous do
        Application.put_env(:loomkin, OpenAICodexModels, previous)
      else
        Application.delete_env(:loomkin, OpenAICodexModels)
      end
    end)

    :ok
  end

  test "lists only codex-visible api-supported models from cache" do
    path =
      write_cache!(%{
        "models" => [
          %{
            "slug" => "gpt-5.4",
            "display_name" => "gpt-5.4",
            "visibility" => "list",
            "supported_in_api" => true,
            "context_window" => 272_000
          },
          %{
            "slug" => "gpt-5.1",
            "display_name" => "gpt-5.1",
            "visibility" => "hide",
            "supported_in_api" => true,
            "context_window" => 272_000
          },
          %{
            "slug" => "gpt-5.3-codex-spark",
            "display_name" => "GPT-5.3-Codex-Spark",
            "visibility" => "list",
            "supported_in_api" => false,
            "context_window" => 128_000
          }
        ]
      })

    Application.put_env(:loomkin, OpenAICodexModels, cache_path: path)

    assert Enum.map(OpenAICodexModels.list_models(), & &1.id) == [
             "gpt-5.4",
             "gpt-5.4-mini",
             "gpt-5.3-codex",
             "gpt-5.2"
           ]
  end

  test "resolves supported cache models into llmdb models" do
    path =
      write_cache!(%{
        "models" => [
          %{
            "slug" => "gpt-5.4",
            "display_name" => "gpt-5.4",
            "visibility" => "list",
            "supported_in_api" => true,
            "context_window" => 272_000,
            "input_modalities" => ["text", "image"]
          }
        ]
      })

    Application.put_env(:loomkin, OpenAICodexModels, cache_path: path)

    assert {:ok, model} = OpenAICodexModels.resolve_model("openai:gpt-5.4")
    assert model.id == "gpt-5.4"
    assert model.provider == :openai
    assert model.name == "gpt-5.4"
    assert model.limits.context == 272_000
    assert :image in model.modalities.input
    assert get_in(model.extra, [:wire, :protocol]) == "openai_responses"
  end

  test "rejects cache models marked unsupported in api" do
    path =
      write_cache!(%{
        "models" => [
          %{
            "slug" => "gpt-5.3-codex-spark",
            "display_name" => "GPT-5.3-Codex-Spark",
            "visibility" => "list",
            "supported_in_api" => false,
            "context_window" => 128_000
          }
        ]
      })

    Application.put_env(:loomkin, OpenAICodexModels, cache_path: path)

    assert {:error, :not_found} = OpenAICodexModels.resolve_model("openai:gpt-5.3-codex-spark")
  end

  test "falls back to built-in gpt-5.4 when cache is unavailable" do
    missing =
      Path.join(
        System.tmp_dir!(),
        "missing-codex-cache-#{System.unique_integer([:positive])}.json"
      )

    Application.put_env(:loomkin, OpenAICodexModels, cache_path: missing)

    assert {:ok, model} = OpenAICodexModels.resolve_model("openai:gpt-5.4")
    assert model.id == "gpt-5.4"
  end

  defp write_cache!(payload) do
    path =
      Path.join(
        System.tmp_dir!(),
        "openai-codex-models-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(payload))
    path
  end
end
