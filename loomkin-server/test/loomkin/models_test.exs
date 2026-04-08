defmodule Loomkin.ModelsTest do
  use Loomkin.DataCase, async: false

  alias Loomkin.Auth.TokenStore
  alias Loomkin.Models

  describe "all_providers_enriched/0" do
    test "surfaces gpt-5.4 for openai api key listings" do
      previous = System.get_env("OPENAI_API_KEY")
      System.put_env("OPENAI_API_KEY", "test-openai-key")

      on_exit(fn ->
        if previous do
          System.put_env("OPENAI_API_KEY", previous)
        else
          System.delete_env("OPENAI_API_KEY")
        end
      end)

      {_provider, _name, {:set, "OPENAI_API_KEY"}, models} =
        Enum.find(Models.all_providers_enriched(), fn {provider, _name, _status, _models} ->
          provider == :openai
        end)

      matching =
        Enum.filter(models, fn {_label, id, _context} ->
          id == "openai:gpt-5.4"
        end)

      assert length(matching) == 1
    end

    test "uses codex-visible openai models for oauth listings" do
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(TokenStore))

      previous = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")

      on_exit(fn ->
        if previous do
          System.put_env("OPENAI_API_KEY", previous)
        else
          System.delete_env("OPENAI_API_KEY")
        end

        TokenStore.revoke_tokens(:openai)
      end)

      :ok =
        TokenStore.store_tokens(:openai, %{
          access_token: "test-openai-token",
          refresh_token: "test-openai-refresh",
          expires_in: 3600,
          account_id: "acct_test",
          scopes: "openid profile email offline_access"
        })

      {_provider, _name, {:oauth, :connected}, models} =
        Enum.find(Models.all_providers_enriched(), fn {provider, _name, _status, _models} ->
          provider == :openai
        end)

      assert Enum.any?(models, fn {_label, id, _context} -> id == "openai:gpt-5.4" end)
      assert Enum.any?(models, fn {_label, id, _context} -> id == "openai:gpt-5.3-codex" end)
      refute Enum.any?(models, fn {_label, id, _context} -> id == "openai:gpt-4o" end)
    end
  end
end
