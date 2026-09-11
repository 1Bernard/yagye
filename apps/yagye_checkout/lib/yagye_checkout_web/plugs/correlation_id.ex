defmodule YagyeCheckoutWeb.Plugs.CorrelationId do
  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    request_id = get_resp_header(conn, "x-request-id") |> List.first()
    Logger.metadata(request_id: request_id)
    assign(conn, :trace_id, request_id)
  end
end
