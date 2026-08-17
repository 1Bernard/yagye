import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Force HTTPS in production — redirects HTTP and sets HSTS headers.
# SSL termination happens at the load balancer; the app enforces the policy.
config :yagye_core, YagyeCoreWeb.Endpoint, force_ssl: [hsts: true]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
