import Config

config :yagye_checkout, YagyeCheckoutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4010],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_checkout_replace_in_prod_must_be_at_least_64_chars_long"

# Core API connection (dev: local yagye_core, same service secret as portal)
config :yagye_checkout,
  core_base_url: "http://localhost:4000",
  core_service_token: "dev_portal_service_secret_change_in_production"

config :logger, level: :debug
