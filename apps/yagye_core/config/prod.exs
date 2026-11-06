import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# force_ssl is set at runtime in config/runtime.exs (gated on FORCE_SSL=true env var)
# so it can be disabled in Docker dev without requiring a rebuild.

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
