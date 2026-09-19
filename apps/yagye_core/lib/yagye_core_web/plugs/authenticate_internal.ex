defmodule YagyeCoreWeb.Plugs.AuthenticateInternal do
  @moduledoc """
  Authenticates inbound requests from internal Yagye services (portal, checkout).

  Each caller must supply two headers:
    X-Service-Name  — identifies the calling service ("portal" or "checkout")
    X-Service-Token — the shared secret for that service

  Core holds a separate secret per service so that a leaked token for one
  caller does not compromise the others. Secrets are set via env vars:
    CORE_PORTAL_SERVICE_SECRET   — portal → core
    CORE_CHECKOUT_SERVICE_SECRET — checkout → core

  Uses constant-time comparison to prevent timing attacks.
  This plug runs on /internal routes only — never on merchant-facing routes.
  """

  @behaviour Plug

  import Plug.Conn

  # Map service name → env var that holds the expected secret.
  @service_secrets %{
    "portal" => "CORE_PORTAL_SERVICE_SECRET",
    "checkout" => "CORE_CHECKOUT_SERVICE_SECRET"
  }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with [service | _] <- get_req_header(conn, "x-service-name"),
         {:ok, env_var} <- Map.fetch(@service_secrets, service),
         expected when is_binary(expected) and byte_size(expected) > 0 <-
           System.get_env(env_var),
         [token | _] <- get_req_header(conn, "x-service-token"),
         true <- Plug.Crypto.secure_compare(token, expected) do
      assign(conn, :service_name, service)
    else
      _ -> halt_unauthorized(conn)
    end
  end

  defp halt_unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{error: %{code: "unauthorized", message: "Invalid service token"}})
    )
    |> halt()
  end
end
