# frozen_string_literal: true

# Faraday wrapper for all portal → Core HTTP calls.
#
# Auth:   X-Service-Token shared secret (CORE_PORTAL_SERVICE_SECRET env var).
# Traces: Forwards the W3C traceparent header so Core's OTel spans are
#         children of the portal request span — one end-to-end trace.
# Errors: All non-2xx responses are mapped to Result structs. Never raises.
class CoreApiClient
  Result = Struct.new(:success?, :body, :error_code, :error_message, keyword_init: true)

  TIMEOUT_SECONDS = 10

  def initialize
    @conn = Faraday.new(url: base_url) do |f|
      f.request  :json
      f.response :json, content_type: /\bjson$/
      f.request  :retry, max: 2, interval: 0.3,
                         retry_statuses: [ 429, 502, 503, 504 ]
      f.adapter  Faraday.default_adapter
      f.options.timeout      = TIMEOUT_SECONDS
      f.options.open_timeout = 5
    end
  end

  # POST /internal/applications/:application_id/approve
  def approve_application(application_code, approved_by:)
    post("/internal/applications/#{application_code}/approve",
         { approved_by: approved_by })
  end

  # POST /internal/applications/:application_id/reject
  def reject_application(application_code, rejected_by:, reason:)
    post("/internal/applications/#{application_code}/reject",
         { rejected_by: rejected_by, reason: reason })
  end

  private

  def post(path, body)
    response = @conn.post(path, body, request_headers)
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Result.new(success?: false, error_code: "network_error", error_message: e.message)
  end

  def handle(response)
    if response.success?
      Result.new(success?: true, body: response.body)
    else
      error = response.body.dig("error") || {}
      Result.new(
        success?:      false,
        body:          response.body,
        error_code:    error["code"]    || response.status.to_s,
        error_message: error["message"] || "Core API error (#{response.status})"
      )
    end
  end

  def request_headers
    {
      "X-Service-Token" => service_secret,
      "traceparent"     => CorrelationId.current
    }
  end

  def base_url
    ENV.fetch("CORE_API_URL", "http://localhost:4000")
  end

  def service_secret
    ENV.fetch("CORE_PORTAL_SERVICE_SECRET") do
      raise "CORE_PORTAL_SERVICE_SECRET is not set — portal cannot call Core"
    end
  end
end
