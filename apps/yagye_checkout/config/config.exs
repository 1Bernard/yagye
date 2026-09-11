import Config

config :yagye_checkout, YagyeCheckoutWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: YagyeCheckoutWeb.ErrorHTML], layout: false],
  pubsub_server: YagyeCheckout.PubSub,
  live_view: [signing_salt: "yagye_checkout"]

config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id]}

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
