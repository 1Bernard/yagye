defmodule YagyeCoreWeb.Plugs.RateLimit do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias YagyeCore.RateLimiter

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if RateLimiter.allow?(ip) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, error_body("rate_limited", "Too many requests — slow down and retry"))
      |> halt()
    end
  end

  defp error_body(code, message) do
    Jason.encode!(%{error: %{code: code, message: message}})
  end
end
