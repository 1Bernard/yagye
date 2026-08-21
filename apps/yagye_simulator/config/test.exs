import Config

config :simulator, Simulator.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :simulator, Simulator.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  server: false

config :simulator, Oban, testing: :inline

config :logger, level: :warning
