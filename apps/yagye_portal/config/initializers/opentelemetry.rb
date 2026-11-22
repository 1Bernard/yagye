# frozen_string_literal: true

# OpenTelemetry SDK is configured in config/application.rb, not here.
# It must run before Rails initializes so the ActionPack Railtie's
# before_initialize hook can insert the Rack tracer middleware with
# the correct options (record_frontend_span: true, use_rack_events: false).
