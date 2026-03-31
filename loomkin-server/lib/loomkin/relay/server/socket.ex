defmodule Loomkin.Relay.Server.Socket do
  @moduledoc """
  Phoenix.Socket for daemon WebSocket connections.

  Authenticates via macaroon daemon token passed as a `token` param on connect.
  Verifies the token signature and caveats, then assigns `user_id`,
  `workspace_id`, and `role` to the socket for use by channels.
  """

  use Phoenix.Socket

  alias Loomkin.Accounts

  channel "daemon:*", Loomkin.Relay.Server.DaemonChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info)
      when is_binary(token) and byte_size(token) > 0 do
    case Accounts.verify_daemon_token(token) do
      {:ok, claims} ->
        socket =
          socket
          |> assign(:user_id, parse_user_id(claims["user_id"]))
          |> assign(:workspace_id, claims["workspace_id"])
          |> assign(:role, claims["role"])

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "daemon_socket:#{socket.assigns.user_id}"

  defp parse_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp parse_user_id(id), do: id
end
