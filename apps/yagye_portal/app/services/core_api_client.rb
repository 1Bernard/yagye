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

  # ── KYB / internal ────────────────────────────────────────────────────────

  # POST /internal/applications/:code/approve
  def approve_application(application_code, approved_by:)
    post("/internal/applications/#{application_code}/approve",
         { approved_by: approved_by })
  end

  # POST /internal/applications/:code/reject
  def reject_application(application_code, rejected_by:, reason:)
    post("/internal/applications/#{application_code}/reject",
         { rejected_by: rejected_by, reason: reason })
  end

  # ── Payments ───────────────────────────────────────────────────────────────

  # POST /v1/payments/:id/refunds
  def create_refund(payment_id, amount:, reason:, initiated_by:)
    post("/v1/payments/#{payment_id}/refunds",
         { amount: amount, reason: reason, initiated_by: initiated_by })
  end

  # GET /v1/payments/:id/events
  def get_payment_events(payment_id)
    get("/v1/payments/#{payment_id}/events")
  end

  # ── API keys ───────────────────────────────────────────────────────────────

  # POST /internal/merchants/:code/keys
  # Uses service-token auth — safe to call before the merchant has any API keys.
  def generate_api_key(merchant_code:, label:, mode:, scopes: [], created_by:)
    post("/internal/merchants/#{merchant_code}/keys",
         { label: label, mode: mode, scopes: scopes, created_by: created_by })
  end

  # DELETE /v1/keys/:key_id
  def revoke_api_key(key_id, revoked_by:)
    delete("/v1/keys/#{key_id}", { revoked_by: revoked_by })
  end

  # ── Webhooks ───────────────────────────────────────────────────────────────

  # POST /v1/webhook-endpoints
  def add_webhook_endpoint(merchant_code:, url:, subscribed_events:, mode:)
    post("/v1/webhook-endpoints",
         { url: url, subscribed_events: subscribed_events, mode: mode })
  end

  # DELETE /v1/webhook-endpoints/:endpoint_id
  def remove_webhook_endpoint(endpoint_id)
    delete("/v1/webhook-endpoints/#{endpoint_id}", {})
  end

  # POST /v1/webhook-endpoints/:endpoint_id/test
  def test_webhook_endpoint(endpoint_id)
    post("/v1/webhook-endpoints/#{endpoint_id}/test", {})
  end

  # ── Routing configurations ─────────────────────────────────────────────────

  def list_routing_configurations(scope: "platform")
    get("/internal/routing-configurations?scope=#{scope}")
  end

  def get_routing_configuration(id)
    get("/internal/routing-configurations/#{id}")
  end

  def create_routing_configuration(name:, scope: "platform", description: nil, graph_payload:)
    post("/internal/routing-configurations",
         { name: name, scope: scope, description: description, graph_payload: graph_payload })
  end

  def update_routing_configuration(id, name:, description: nil, graph_payload:)
    patch("/internal/routing-configurations/#{id}",
          { name: name, description: description, graph_payload: graph_payload })
  end

  def publish_routing_configuration(id)
    post("/internal/routing-configurations/#{id}/publish", {})
  end

  # ── Adjustment approvals (ops — SoD enforced in Core) ─────────────────────

  # POST /internal/adjustment_approvals/:break_id/approve
  def approve_adjustment(break_id:, approved_by:)
    post("/internal/adjustment_approvals/#{break_id}/approve", { approved_by: approved_by })
  end

  # POST /internal/adjustment_approvals/:break_id/reject
  def reject_adjustment(break_id:, rejected_reason:)
    post("/internal/adjustment_approvals/#{break_id}/reject", { rejected_reason: rejected_reason })
  end

  private

  def post(path, body)
    response = @conn.post(path, body, request_headers)
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Result.new(success?: false, error_code: "network_error", error_message: e.message)
  end

  def get(path)
    response = @conn.get(path, nil, request_headers)
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Result.new(success?: false, error_code: "network_error", error_message: e.message)
  end

  def delete(path, body)
    response = @conn.delete(path, body, request_headers)
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Result.new(success?: false, error_code: "network_error", error_message: e.message)
  end

  def patch(path, body)
    response = @conn.patch(path, body, request_headers)
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
