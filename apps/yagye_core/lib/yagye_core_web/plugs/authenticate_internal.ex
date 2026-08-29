defmodule YagyeCoreWeb.Plugs.AuthenticateInternal do
  @moduledoc """
  Authenticates inbound requests from the Yagye Portal (service-to-service).

  Reads the X-Service-Token header and compares it against the
  CORE_PORTAL_SERVICE_SECRET environment variable using a constant-time
  comparison to prevent timing attacks.

  This plug is used on the /internal pipeline — never on merchant-facing routes.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    expected = System.get_env("CORE_PORTAL_SERVICE_SECRET")

    case get_req_header(conn, "x-service-token") do
      [token | _] when is_binary(expected) and byte_size(expected) > 0 ->
        if Plug.Crypto.secure_compare(token, expected) do
          conn
        else
          halt_unauthorized(conn)
        end

      _ ->
        halt_unauthorized(conn)
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
