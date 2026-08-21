import Config

config :simulator, Simulator.Repo,
  database: "gateway_simulator_#{config_env()}",
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  pool_size: 10

config :simulator, Simulator.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4100],
  server: true,
  render_errors: [
    formats: [json: Simulator.Web.ErrorJSON],
    layout: false
  ]

config :simulator, :ecto_repos, [Simulator.Repo]

config :simulator, Oban,
  repo: Simulator.Repo,
  queues: [webhooks: 5, wallet_prompts: 10]

config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id]}

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
