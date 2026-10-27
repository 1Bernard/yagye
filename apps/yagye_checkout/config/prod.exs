import Config

# Do not print debug messages in production
config :logger, level: :info

# Force HTTPS in production — SSL termination at the load balancer.
config :yagye_checkout, YagyeCheckoutWeb.Endpoint, force_ssl: [hsts: true]

# Runtime production configuration (env vars) is in config/runtime.exs.
