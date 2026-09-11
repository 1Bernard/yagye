import Config

config :yagye_checkout, YagyeCheckoutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base: "test_secret_key_base_checkout_at_least_64_chars_long_xxxxxxxxxxxxxxxxxx"

config :yagye_checkout,
  core_base_url: "http://localhost:4000",
  core_service_token: "test-checkout-service-token"

config :logger, level: :warning
