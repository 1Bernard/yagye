# frozen_string_literal: true

# Reads the W3C traceparent header (or X-Request-ID fallback) from each
# inbound request and stores the trace/correlation ID in RequestStore so
# any code in the request lifecycle — controllers, service objects,
# background jobs via thread — can call CorrelationId.current.
#
# Also stamps the ID onto every Rails logger tagged entry and writes it
# back in the X-Request-ID response header so clients can correlate logs.
class CorrelationIdMiddleware
  TRACEPARENT_HEADER = "HTTP_TRACEPARENT"
  REQUEST_ID_HEADER  = "HTTP_X_REQUEST_ID"

  def initialize(app)
    @app = app
  end

  def call(env)
    id = extract_id(env)
    CorrelationId.current = id

    Rails.logger.tagged(id) do
      status, headers, body = @app.call(env)
      headers["X-Request-ID"] = id
      [ status, headers, body ]
    end
  ensure
    CorrelationId.clear
  end

  private

  def extract_id(env)
    # Prefer W3C traceparent — parse out the trace-id segment (chars 3..34)
    if (tp = env[TRACEPARENT_HEADER].presence)
      parts = tp.split("-")
      parts[1].presence || SecureRandom.hex(16)
    elsif (rid = env[REQUEST_ID_HEADER].presence)
      rid.gsub(/[^a-zA-Z0-9\-_]/, "").first(64)
    else
      SecureRandom.hex(16)
    end
  end
end
