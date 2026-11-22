# frozen_string_literal: true

# Reads the W3C traceparent header from each inbound request and stores
# the OTel trace ID in RequestStore so any code in the request lifecycle —
# controllers, service objects, background jobs via thread — can call
# CorrelationId.current. Falls back to the OTel span created by the Rack
# instrumentation when no inbound traceparent is present.
#
# X-Request-ID (injected by Caddy) is intentionally ignored: using it would
# make the correlation ID in logs and the DB diverge from the trace ID in
# Tempo, breaking log→trace linking in Grafana.
#
# Also stamps the trace ID onto every Rails logger tagged entry and writes it
# back in the X-Request-ID response header so clients can correlate logs.
class CorrelationIdMiddleware
  TRACEPARENT_HEADER = "HTTP_TRACEPARENT"

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
    if (tp = env[TRACEPARENT_HEADER].presence)
      # Extract trace-id segment (index 1) from W3C "00-<trace-id>-<span-id>-<flags>".
      # OTel Rack middleware runs before us and has already set the span context,
      # so otel_trace_id() is available as the fallback if the header is malformed.
      parts = tp.split("-")
      parts[1].presence || otel_trace_id
    else
      # No inbound traceparent — use the OTel trace ID from the Rack-instrumented span.
      # This keeps logs, DB records, and Tempo on the same identifier.
      otel_trace_id
    end
  end

  def otel_trace_id
    ctx = OpenTelemetry::Trace.current_span.context
    ctx.valid? ? ctx.hex_trace_id : SecureRandom.hex(16)
  end
end
