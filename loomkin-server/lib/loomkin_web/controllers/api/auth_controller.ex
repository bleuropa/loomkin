defmodule LoomkinWeb.Api.AuthController do
  use LoomkinWeb, :controller

  alias Loomkin.Accounts

  action_fallback LoomkinWeb.Api.FallbackController

  @doc """
  POST /api/v1/auth/register
  Creates a new user account and returns a bearer token.
  """
  def register(conn, %{"email" => email} = params) do
    case Accounts.register_user(%{email: email, password: params["password"]}) do
      {:ok, user} ->
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:created)
        |> json(%{
          token: Base.url_encode64(token),
          user: serialize_user(user)
        })

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  POST /api/v1/auth/anonymous
  Creates an anonymous user account and returns a bearer token.
  """
  def anonymous(conn, _params) do
    anon_email = "anon-#{Base.url_encode64(:crypto.strong_rand_bytes(12))}@anonymous.local"

    case Accounts.register_user(%{email: anon_email}) do
      {:ok, user} ->
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:created)
        |> json(%{
          token: Base.url_encode64(token),
          user: serialize_user(user)
        })

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  POST /api/v1/auth/login
  If `password` is provided and valid, returns a bearer token directly.
  Otherwise sends a magic link login email and returns 200 regardless of whether the email exists.
  """
  def login(conn, %{"email" => email, "password" => password})
      when is_binary(password) and password != "" do
    case Accounts.get_user_by_email_and_password(email, password) do
      %{} = user ->
        token = Accounts.generate_user_session_token(user)

        json(conn, %{
          token: Base.url_encode64(token),
          user: serialize_user(user)
        })

      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid email or password"})
    end
  end

  def login(conn, %{"email" => email}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(user, fn token ->
        "loomkin://auth/confirm?token=#{token}"
      end)
    end

    json(conn, %{message: "if the email is registered, you will receive a login link"})
  end

  @doc """
  POST /api/v1/auth/login/confirm
  Confirms a magic link token and returns a bearer token.
  """
  def confirm(conn, %{"token" => token}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        session_token = Accounts.generate_user_session_token(user)

        json(conn, %{
          token: Base.url_encode64(session_token),
          user: serialize_user(user)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_token", message: "token is invalid or expired"})
    end
  end

  @doc """
  POST /api/v1/auth/logout
  Deletes the current session token.
  """
  def logout(conn, _params) do
    with ["Bearer " <> encoded_token] <- get_req_header(conn, "authorization"),
         {:ok, token} <- Base.url_decode64(encoded_token) do
      Accounts.delete_user_session_token(token)
    end

    json(conn, %{message: "logged out"})
  end

  @doc """
  GET /api/v1/auth/me
  Returns the current user's profile.
  """
  def me(conn, _params) do
    user = conn.assigns.current_scope.user
    json(conn, %{user: serialize_user(user)})
  end

  @doc """
  POST /api/v1/auth/bootstrap
  Accepts a loomkin.dev cloud token, validates it against loomkin.dev,
  creates or links a local user, and returns a local session token.
  """
  def bootstrap(conn, %{"cloud_token" => cloud_token}) do
    cloud_url = System.get_env("LOOMKIN_CLOUD_URL") || "https://loomkin.dev"

    case verify_cloud_token(cloud_url, cloud_token) do
      {:ok, cloud_user} ->
        cloud_id = to_string(cloud_user["id"])

        attrs = %{
          email: cloud_user["email"],
          username: cloud_user["username"],
          display_name: cloud_user["display_name"],
          avatar_url: cloud_user["avatar_url"]
        }

        case Accounts.find_or_create_user_by_cloud_id(cloud_id, attrs) do
          {:ok, user} ->
            token = Accounts.generate_user_session_token(user)

            conn
            |> put_status(:created)
            |> json(%{
              token: Base.url_encode64(token),
              user: serialize_user(user)
            })

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_cloud_token", message: "Cloud token is invalid or expired"})

      {:error, :unreachable} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "cloud_unreachable",
          message: "Could not reach loomkin.dev to verify token"
        })
    end
  end

  defp verify_cloud_token(cloud_url, token) do
    url = "#{cloud_url}/api/v1/auth/me"
    headers = [{"authorization", "Bearer #{token}"}, {"content-type", "application/json"}]

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"user" => user}}} ->
        {:ok, user}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :unauthorized}

      _ ->
        {:error, :unreachable}
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      username: user.username,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at
    }
  end
end
