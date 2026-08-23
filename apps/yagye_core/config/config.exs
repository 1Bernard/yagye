# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :yagye_core,
  ecto_repos: [YagyeCore.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :yagye_core, YagyeCoreWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: YagyeCoreWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: YagyeCore.PubSub,
  live_view: [signing_salt: "xZXQZzdj"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :yagye_core, YagyeCore.Mailer, adapter: Swoosh.Adapters.Local

# Structured JSON logging — includes request_id in every line for correlation
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id]}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban — PostgreSQL-backed job queue.
# Queues are defined here; workers are added as they are introduced.
# testing: Oban.Testing is used in tests instead of running real queues.
config :yagye_core,
  provider_adapter: YagyeCore.Payments.Adapters.SimulatorAdapter,
  # 32-byte hex key for AES-256-GCM credential encryption. Override in prod via env.
  credential_encryption_key: "0000000000000000000000000000000000000000000000000000000000000001"

config :yagye_core, Oban,
  repo: YagyeCore.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Relay runs every minute; self-reschedules immediately on a full batch
       {"* * * * *", YagyeCore.Events.Workers.OutboxRelayWorker},
       # Daily metrics recomputed hourly
       {"0 * * * *", YagyeCore.Projections.Workers.DailyMetricsWorker}
     ]}
  ],
  queues: [
    payments: 10,
    events: 5,
    projections: 10
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
