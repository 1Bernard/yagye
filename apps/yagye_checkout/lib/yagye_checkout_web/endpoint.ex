defmodule YagyeCheckoutWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :yagye_checkout

  @session_options [
    store: :cookie,
    key: "_yagye_checkout_key",
    signing_salt: "ckO9rPvQ",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :yagye_checkout,
    gzip: not code_reloading?,
    only: ~w(assets fonts images favicon.ico robots.txt)

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug YagyeCheckoutWeb.Plugs.CorrelationId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug YagyeCheckoutWeb.Router
end
