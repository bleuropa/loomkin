defmodule LoomkinWeb.FederationController do
  @moduledoc """
  Serves federation-related endpoints for DID document discovery.

  - `GET /.well-known/did.json` - instance-level DID document
  """

  use LoomkinWeb, :controller

  alias Loomkin.Federation.DidDocument
  alias Loomkin.Federation.Identity

  @doc """
  Serve the instance-level DID document at `/.well-known/did.json`.

  Loads (or generates) the instance keypair and builds the DID document
  using the configured domain.
  """
  def did_document(conn, _params) do
    config = Application.get_env(:loomkin, Identity, [])
    domain = Keyword.get(config, :domain, "localhost")

    case Identity.get_or_create_keypair() do
      {:ok, keypair} ->
        doc =
          DidDocument.build(
            domain: domain,
            public_key: keypair.public
          )

        conn
        |> put_resp_content_type("application/did+ld+json")
        |> json(doc)

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to load identity", detail: inspect(reason)})
    end
  end
end
