require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Configure OpenTelemetry after Bundler loads the gems but before initialize!
# runs, so the ActionPack Railtie's before_initialize hook finds the Rack
# instrumentation already installed with our custom options.
OpenTelemetry::SDK.configure do |c|
  c.service_name    = ENV.fetch("OTEL_SERVICE_NAME", "yagye_portal")
  c.service_version = "1.0.0"
  c.use_all(
    "OpenTelemetry::Instrumentation::Rack" => {
      record_frontend_span: true,
      use_rack_events:      false
    }
  )
end

module YagyePortal
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.autoload_paths += [
      Rails.root.join("app/views"),
      Rails.root.join("app/queries"),
      Rails.root.join("app/services"),
      Rails.root.join("app/middleware")
    ]
    config.eager_load_paths << Rails.root.join("app/views")
    Rails.autoloaders.main.collapse(Rails.root.join("app/views/components"))

    # Rack::Attack and RequestStore::Middleware are inserted automatically by
    # their respective Railties — no explicit use needed here.

    # Correlation ID + structured logging middleware (runs before Devise/auth).
    # Explicit require because application.rb runs before Zeitwerk is active.
    require_relative "../app/middleware/correlation_id"
    require_relative "../app/middleware/correlation_id_middleware"
    config.middleware.use CorrelationIdMiddleware

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
