defmodule LoomkinWeb.FederationControllerTest do
  use LoomkinWeb.ConnCase, async: false

  alias Loomkin.Federation.Identity

  @tmp_dir "tmp/test_federation_keys_#{System.unique_integer([:positive])}"

  setup do
    File.rm_rf!(@tmp_dir)

    original = Application.get_env(:loomkin, Identity, [])

    Application.put_env(:loomkin, Identity,
      domain: "test.loomkin.dev",
      key_path: @tmp_dir
    )

    on_exit(fn ->
      Application.put_env(:loomkin, Identity, original)
      File.rm_rf!(@tmp_dir)
    end)

    :ok
  end

  describe "GET /.well-known/did.json" do
    test "returns a valid DID document", %{conn: conn} do
      conn = get(conn, "/.well-known/did.json")

      assert json_response(conn, 200)
      body = json_response(conn, 200)

      assert body["@context"] == [
               "https://www.w3.org/ns/did/v1",
               "https://w3id.org/security/suites/ed25519-2020/v1"
             ]

      assert body["id"] == "did:web:test.loomkin.dev"
      assert is_list(body["verificationMethod"])
      assert length(body["verificationMethod"]) == 1

      [vm] = body["verificationMethod"]
      assert vm["type"] == "Ed25519VerificationKey2020"
      assert String.starts_with?(vm["publicKeyMultibase"], "z")
    end

    test "returns the same keypair on subsequent requests", %{conn: conn} do
      conn1 = get(conn, "/.well-known/did.json")
      body1 = json_response(conn1, 200)

      conn2 = get(build_conn(), "/.well-known/did.json")
      body2 = json_response(conn2, 200)

      [vm1] = body1["verificationMethod"]
      [vm2] = body2["verificationMethod"]
      assert vm1["publicKeyMultibase"] == vm2["publicKeyMultibase"]
    end

    test "sets the correct content type", %{conn: conn} do
      conn = get(conn, "/.well-known/did.json")

      content_type =
        conn
        |> get_resp_header("content-type")
        |> List.first()

      assert content_type =~ "application/did+ld+json"
    end
  end
end
