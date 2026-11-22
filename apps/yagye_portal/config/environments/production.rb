require "active_support/core_ext/integer/time"
require "socket"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # All traffic arrives via an SSL-terminating reverse proxy in production.
  # Set PORTAL_DISABLE_SSL=true in Docker local dev (Thruster has no cert).
  _ssl_enabled = !ENV["PORTAL_DISABLE_SSL"]
  config.assume_ssl = _ssl_enabled
  config.force_ssl  = _ssl_enabled
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("PORTAL_HOST", "portal.yagye.com") }

  # Allow route URL helpers used outside of request context (e.g. models) to generate absolute URLs.
  config.after_initialize do
    Rails.application.routes.default_url_options = { host: ENV.fetch("PORTAL_HOST", "portal.yagye.com"), protocol: "https" }
  end

  # SMTP relay for transactional email.
  # Docker dev: SMTP_HOST=mailpit, SMTP_PORT=1025, no auth, no TLS → Mailpit catches all mail.
  # Production: SMTP_HOST=email-smtp.<region>.amazonaws.com, SMTP_PORT=587, SES SMTP credentials.
  config.action_mailer.delivery_method      = :smtp
  config.action_mailer.perform_deliveries   = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_HOST", "smtp-relay.brevo.com"),
    port:                 ENV.fetch("SMTP_PORT", "587").to_i,
    user_name:            ENV["SMTP_USER"],
    password:             ENV["SMTP_PASSWORD"],
    authentication:       ENV["SMTP_USER"].present? ? :login : nil,
    enable_starttls_auto: ENV.fetch("SMTP_TLS", "true") == "true"
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding protection — only accept requests for our own host.
  config.hosts = [ ENV.fetch("PORTAL_HOST", "portal.yagye.com") ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Request logging is handled by config/initializers/request_logging.rb which
  # subscribes directly to process_action.action_controller and writes JSON to
  # fd/1. Lograge is disabled because it doesn't flush reliably under
  # Puma 8 + Thruster in Rails 8.1.
  config.lograge.enabled = false
end
