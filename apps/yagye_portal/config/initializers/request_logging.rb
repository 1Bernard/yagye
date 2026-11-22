# frozen_string_literal: true

# One structured JSON line per request → STDOUT → Docker log driver → Loki.
# Logging itself is in ApplicationController#log_request_json (around_action),
# which covers all requests including Devise controllers.  This initializer just
# ensures STDOUT is unbuffered so lines appear in Docker logs immediately.
return unless Rails.env.production?

STDOUT.sync = true
