import Config

config :simulator, Simulator.Repo, show_sensitive_data_on_connection_error: true

config :logger, level: :debug

config :simulator, Simulator.Web.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: []

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4318"
