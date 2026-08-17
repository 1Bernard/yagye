defmodule YagyeCoreWeb.CachingBodyReader do
  @moduledoc false

  # Wraps Plug.Conn.read_body/2 and appends the raw bytes to conn.assigns.raw_body.
  # Plug.Parsers consumes the body stream once; this saves it so the Idempotency
  # plug can hash it for the request fingerprint without re-reading a spent stream.
  #
  # Configured in the endpoint:
  #   plug Plug.Parsers, body_reader: {YagyeCoreWeb.CachingBodyReader, :read_body, []}

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    cached = (conn.assigns[:raw_body] || "") <> body
    conn = Plug.Conn.assign(conn, :raw_body, cached)
    {:ok, body, conn}
  end
end
