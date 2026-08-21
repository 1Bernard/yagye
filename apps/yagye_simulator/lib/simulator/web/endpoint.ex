defmodule Simulator.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :simulator

  @session_options [
    store: :cookie,
    key: "_simulator_key",
    signing_salt: "sim_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session, @session_options
  plug Simulator.Web.Router
end
