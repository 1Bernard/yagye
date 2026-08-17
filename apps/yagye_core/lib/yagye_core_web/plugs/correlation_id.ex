defmodule YagyeCoreWeb.Plugs.CorrelationId do
  @moduledoc """
  Reads the request ID assigned by Plug.RequestId and puts it into Logger
  metadata so every log line emitted during the request carries it.

  Must be placed after Plug.RequestId in the endpoint pipeline.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    request_id = get_resp_header(conn, "x-request-id") |> List.first()
    Logger.metadata(request_id: request_id)
    conn
  end
end
