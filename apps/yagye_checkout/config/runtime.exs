import Config

:logger.update_primary_config(%{
  metadata: %{
    service:     "yagye_checkout",
    environment: config_env() |> to_string(),
    release:     System.get_env("RELEASE_SHA", "local"),
    host:        System.get_env("HOSTNAME", "localhost")
  }
})

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing"

  host = System.get_env("PHX_HOST") || "pay.yagye.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :yagye_checkout, YagyeCheckoutWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :yagye_checkout,
    core_base_url:
      System.get_env("CORE_BASE_URL") ||
        raise("environment variable CORE_BASE_URL is missing"),
    core_service_token:
      System.get_env("CORE_CHECKOUT_SERVICE_SECRET") ||
        raise("environment variable CORE_CHECKOUT_SERVICE_SECRET is missing")
end
