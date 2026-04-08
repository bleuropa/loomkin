defmodule Loomkin.LLMTest do
  use ExUnit.Case, async: true

  alias Loomkin.LLM
  alias Loomkin.Providers.OpenAIOAuth

  describe "oauth_providers/0" do
    test "returns a map of base provider to oauth provider" do
      map = LLM.oauth_providers()
      assert is_map(map)
      assert map["anthropic"] == "anthropic_oauth"
      assert map["google"] == "google_oauth"
      assert map["openai"] == "openai_oauth"
    end
  end

  describe "oauth_active?/1" do
    test "returns false when provider has no active token" do
      # OpenAI is OAuth-capable, but TokenStore has no tokens in the test env
      refute LLM.oauth_active?("openai")
    end

    test "returns false for unknown provider" do
      refute LLM.oauth_active?("nonexistent")
    end

    test "returns false for empty string" do
      refute LLM.oauth_active?("")
    end

    test "returns a boolean for known OAuth-capable provider" do
      # In test, TokenStore may or may not have tokens
      result = LLM.oauth_active?("anthropic")
      assert is_boolean(result)
    end
  end

  describe "stream_backed_generate?/1" do
    test "uses stream-backed generate for openai codex oauth" do
      assert LLM.stream_backed_generate?(OpenAIOAuth)
    end

    test "does not force stream-backed generate for other providers" do
      refute LLM.stream_backed_generate?(ReqLLM.Providers.OpenAI)
    end
  end
end
