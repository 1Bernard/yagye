import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :yagye_core, YagyeCore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "yagye_core_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :yagye_core, YagyeCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "q/rDYHIazZmFN8hRrzRzdDGLnqXf3UW/fjoDnOEy7zThri8bRIISTSlsDDnrp0z0",
  server: false

# In test we don't send emails
config :yagye_core, YagyeCore.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Speed up Argon2 in tests — never use in prod
config :argon2_elixir, t_cost: 1, m_cost: 8

# Oban — disable queues and plugins in tests; use Oban.Testing helpers instead
config :yagye_core, Oban, testing: :manual

# Use Mox mock adapter in tests — no real HTTP calls
config :yagye_core, :provider_adapter, YagyeCore.MockProviderAdapter

config :opentelemetry, traces_exporter: :none
