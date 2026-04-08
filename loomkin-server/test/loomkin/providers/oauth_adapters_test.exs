defmodule Loomkin.Providers.OAuthAdaptersTest do
  @moduledoc """
  Integration tests for OAuth ReqLLM adapters (AnthropicOAuth, OpenAIOAuth, GoogleOAuth).

  Tests token retrieval, model name resolution, build_authorize_url return types,
  and error handling without making HTTP requests.
  """

  use Loomkin.DataCase, async: false

  alias Loomkin.Auth.TokenStore
  alias Loomkin.Providers.{AnthropicOAuth, OpenAICodexModels, OpenAIOAuth, GoogleOAuth}

  setup do
    # Ensure no stale tokens leak between tests
    for provider <- [:anthropic, :openai, :google] do
      TokenStore.revoke_tokens(provider)
    end

    on_exit(fn ->
      for provider <- [:anthropic, :openai, :google] do
        TokenStore.revoke_tokens(provider)
      end
    end)

    :ok
  end

  # ── Token retrieval — no token → clean error ───────────────────────

  describe "prepare_request returns {:error, :no_oauth_token} when no token stored" do
    test "AnthropicOAuth" do
      assert {:error, :no_oauth_token} =
               AnthropicOAuth.prepare_request(
                 :chat,
                 "anthropic_oauth:claude-sonnet-4-6",
                 "hi",
                 []
               )
    end

    test "OpenAIOAuth" do
      assert {:error, :no_oauth_token} =
               OpenAIOAuth.prepare_request(:chat, "openai_oauth:gpt-4o", "hi", [])
    end

    test "GoogleOAuth" do
      assert {:error, :no_oauth_token} =
               GoogleOAuth.prepare_request(:chat, "google_oauth:gemini-2.0-flash", "hi", [])
    end
  end

  # ── Token retrieval — with token, fetch succeeds ───────────────────

  describe "prepare_request gets past token fetch when token is stored" do
    test "AnthropicOAuth does not return :no_oauth_token" do
      store_test_token(:anthropic, "test-anthropic-token")

      result =
        try do
          AnthropicOAuth.prepare_request(:chat, "anthropic_oauth:claude-sonnet-4-6", "hello", [])
        rescue
          # May raise from deep Req option registration — that's fine,
          # it means we got past the token fetch
          ArgumentError -> :got_past_token_fetch
        end

      # May fail downstream (model resolution, Req options, etc.) but must NOT
      # fail with :no_oauth_token — that proves the token was fetched
      refute match?({:error, :no_oauth_token}, result)
    end

    test "OpenAIOAuth does not return :no_oauth_token" do
      store_test_token(:openai, "test-openai-token")

      result =
        try do
          OpenAIOAuth.prepare_request(:chat, "openai_oauth:gpt-4o", "hello", [])
        rescue
          # May raise from deep Req option registration — that's fine,
          # it means we got past the token fetch
          ArgumentError -> :got_past_token_fetch
        end

      refute match?({:error, :no_oauth_token}, result)
    end

    test "GoogleOAuth does not return :no_oauth_token" do
      store_test_token(:google, "test-google-token")

      result =
        try do
          GoogleOAuth.prepare_request(:chat, "google_oauth:gemini-2.0-flash", "hello", [])
        rescue
          ArgumentError -> :got_past_token_fetch
        end

      refute match?({:error, :no_oauth_token}, result)
    end
  end

  # ── build_authorize_url returns {:ok, url} ─────────────────────────

  describe "build_authorize_url returns {:ok, url} tuple" do
    test "Anthropic" do
      params = %{
        state: "test-state",
        code_verifier: "test-verifier-12345678901234567890123456789012"
      }

      assert {:ok, url} = Loomkin.Auth.Providers.Anthropic.build_authorize_url(params)
      assert String.starts_with?(url, "https://claude.ai/oauth/authorize?")
      assert String.contains?(url, "state=test-state")
    end

    test "OpenAI" do
      params = %{
        state: "test-state",
        code_verifier: "test-verifier-12345678901234567890123456789012",
        redirect_uri: "http://localhost:4000/auth/openai/callback"
      }

      assert {:ok, url} = Loomkin.Auth.Providers.OpenAI.build_authorize_url(params)
      assert String.starts_with?(url, "https://auth.openai.com/oauth/authorize?")
      assert String.contains?(url, "state=test-state")
    end
  end

  # ── Unsupported operations ─────────────────────────────────────────

  describe "unsupported operations return errors" do
    test "AnthropicOAuth rejects :embedding" do
      assert {:error, _} =
               AnthropicOAuth.prepare_request(:embedding, "anthropic_oauth:model", "hi", [])
    end

    test "OpenAIOAuth rejects :embedding" do
      assert {:error, _} =
               OpenAIOAuth.prepare_request(:embedding, "openai_oauth:model", "hi", [])
    end

    test "GoogleOAuth rejects :transcription" do
      assert {:error, _} =
               GoogleOAuth.prepare_request(:transcription, "google_oauth:model", "hi", [])
    end
  end

  describe "OpenAIOAuth codex request shaping" do
    test "builds a request for gpt-5.4 when ReqLLM catalog is stale" do
      store_test_token(:openai, "test-openai-token")

      assert {:ok, %Req.Request{} = request} =
               OpenAIOAuth.prepare_request(:chat, "openai:gpt-5.4", "hello", [])

      assert request.options[:model] == "gpt-5.4"
      assert request.options[:base_url] == "https://chatgpt.com/backend-api"
    end

    test "falls back to stored account id when token claims are unavailable" do
      store_test_token(:openai, "test-openai-token")

      assert {:ok, %Req.Request{} = request} =
               OpenAIOAuth.prepare_request(:chat, "openai:gpt-5.4", "hello", [])

      assert request.headers["chatgpt-account-id"] == ["test-account-openai"]
    end

    test "replays tool call and output without previous_response_id for codex resume flow" do
      store_test_token(:openai, "test-openai-token")

      messages = [
        ReqLLM.Context.assistant("",
          tool_calls: [{"echo", %{text: "hi"}, id: "call_123"}],
          metadata: %{response_id: "resp_123"}
        ),
        ReqLLM.Context.tool_result("call_123", "done")
      ]

      assert {:ok, %Req.Request{} = request} =
               OpenAIOAuth.prepare_request(:chat, "openai:gpt-5.4", messages, [])

      encoded = OpenAIOAuth.encode_body(request)
      body = Jason.decode!(encoded.body)

      refute Map.has_key?(body, "previous_response_id")

      assert Enum.any?(body["input"], fn item ->
               item["type"] == "function_call" and item["call_id"] == "call_123" and
                 item["name"] == "echo"
             end)

      assert Enum.any?(body["input"], fn item ->
               item["type"] == "function_call_output" and item["call_id"] == "call_123" and
                 item["output"] == "done"
             end)
    end

    test "stream requests also drop previous_response_id for codex resume flow" do
      store_test_token(:openai, "test-openai-token")

      messages = [
        ReqLLM.Context.assistant("",
          tool_calls: [{"echo", %{text: "hi"}, id: "call_123"}],
          metadata: %{response_id: "resp_123"}
        ),
        ReqLLM.Context.tool_result("call_123", "done")
      ]

      {:ok, model} = OpenAICodexModels.resolve_model("openai:gpt-5.4")

      context = ReqLLM.Context.new(messages)

      assert {:ok, %Finch.Request{body: body}} =
               OpenAIOAuth.attach_stream(model, context, [], nil)

      decoded = Jason.decode!(body)

      refute Map.has_key?(decoded, "previous_response_id")

      assert Enum.any?(decoded["input"], fn item ->
               item["type"] == "function_call" and item["call_id"] == "call_123"
             end)

      assert Enum.any?(decoded["input"], fn item ->
               item["type"] == "function_call_output" and item["call_id"] == "call_123"
             end)
    end

    test "drops stale historical function calls on follow-up turns" do
      store_test_token(:openai, "test-openai-token")

      messages = [
        ReqLLM.Context.user("first question"),
        ReqLLM.Context.assistant("",
          tool_calls: [{"echo", %{text: "hi"}, id: "call_123"}],
          metadata: %{response_id: "resp_123"}
        ),
        ReqLLM.Context.tool_result("call_123", "done"),
        ReqLLM.Context.assistant("All set.", metadata: %{response_id: "resp_124"}),
        ReqLLM.Context.user("second question")
      ]

      assert {:ok, %Req.Request{} = request} =
               OpenAIOAuth.prepare_request(:chat, "openai:gpt-5.4", messages, [])

      encoded = OpenAIOAuth.encode_body(request)
      body = Jason.decode!(encoded.body)

      refute Enum.any?(body["input"], &(&1["type"] == "function_call"))
      refute Enum.any?(body["input"], &(&1["type"] == "function_call_output"))

      assert Enum.any?(body["input"], fn item ->
               item["role"] == "user"
             end)
    end

    test "stream follow-up turns also drop stale historical function calls" do
      store_test_token(:openai, "test-openai-token")

      messages = [
        ReqLLM.Context.user("first question"),
        ReqLLM.Context.assistant("",
          tool_calls: [{"echo", %{text: "hi"}, id: "call_123"}],
          metadata: %{response_id: "resp_123"}
        ),
        ReqLLM.Context.tool_result("call_123", "done"),
        ReqLLM.Context.assistant("All set.", metadata: %{response_id: "resp_124"}),
        ReqLLM.Context.user("second question")
      ]

      {:ok, model} = OpenAICodexModels.resolve_model("openai:gpt-5.4")
      context = ReqLLM.Context.new(messages)

      assert {:ok, %Finch.Request{body: body}} =
               OpenAIOAuth.attach_stream(model, context, [], nil)

      decoded = Jason.decode!(body)

      refute Enum.any?(decoded["input"], &(&1["type"] == "function_call"))
      refute Enum.any?(decoded["input"], &(&1["type"] == "function_call_output"))

      assert Enum.any?(decoded["input"], fn item ->
               item["role"] == "user"
             end)
    end

    test "moves system input text into instructions" do
      body = %{
        "input" => [
          %{
            "role" => "system",
            "content" => [%{"type" => "input_text", "text" => "be concise"}]
          },
          %{
            "role" => "user",
            "content" => [%{"type" => "input_text", "text" => "hello"}]
          }
        ]
      }

      patched = OpenAIOAuth.inject_instructions_from_input(body)

      assert patched["instructions"] == "be concise"
      assert Enum.all?(patched["input"], &(&1["role"] != "system"))
    end

    test "drops max_output_tokens for codex backend" do
      body = %{
        "input" => [
          %{
            "role" => "user",
            "content" => [%{"type" => "input_text", "text" => "hello"}]
          }
        ],
        "max_output_tokens" => 1024
      }

      patched = OpenAIOAuth.inject_instructions_from_input(body)

      refute Map.has_key?(patched, "max_output_tokens")
    end

    test "decodes responses api stream deltas" do
      {:ok, model} = ReqLLM.model("openai:gpt-5.3-codex")

      event = %{
        data: %{
          "event" => "response.output_text.delta",
          "delta" => "hello"
        }
      }

      chunks = OpenAIOAuth.decode_stream_event(event, model)

      assert Enum.any?(chunks, fn chunk ->
               chunk.type == :content and chunk.text == "hello"
             end)
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp store_test_token(provider, access_token) do
    token_data = %{
      access_token: access_token,
      refresh_token: "test-refresh-token",
      expires_in: 3600,
      account_id: "test-account-#{provider}",
      scopes: "test"
    }

    :ok = TokenStore.store_tokens(provider, token_data)
  end
end
