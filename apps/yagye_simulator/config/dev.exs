import Config

config :simulator, Simulator.Repo, show_sensitive_data_on_connection_error: true

config :logger, level: :debug

config :logger, :default_handler,
  formatter: Logger.Formatter.new(
    format: "[$level] $message $metadata\n",
    metadata: [:request_id, :trace, :span],
    colors: [enabled: true]
  )

config :simulator, Simulator.Web.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: []

config :opentelemetry, traces_exporter: :none
