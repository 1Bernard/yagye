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
                         retry_statuses: [ 429, 502, 503, 504 ],
                         exceptions:     [ Faraday::TooManyRequestsError ]
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

  # ── Invoices (P13) ────────────────────────────────────────────────────────

  # GET /internal/merchants/:code/invoices
  def list_invoices(merchant_code:, state: nil, starting_after: nil)
    query = { merchant_code: merchant_code }
    query[:state]          = state          if state
    query[:starting_after] = starting_after if starting_after
    get("/internal/merchants/#{merchant_code}/invoices?#{URI.encode_www_form(query.transform_keys(&:to_s))}")
  end

  # GET /internal/invoices/:id
  def get_invoice(public_id)
    get("/internal/invoices/#{public_id}")
  end

  # POST /internal/invoices
  def create_invoice(merchant_code:, **attrs)
    post("/internal/invoices", attrs.merge(merchant_code: merchant_code))
  end

  # POST /internal/invoices/:id/issue
  def issue_invoice(public_id)
    post("/internal/invoices/#{public_id}/issue", {})
  end

  # POST /internal/invoices/:id/void
  def void_invoice(public_id)
    post("/internal/invoices/#{public_id}/void", {})
  end

  # ── Checkout Sessions (P16) ───────────────────────────────────────────────

  # GET /internal/merchants/:code/checkout-sessions
  def list_checkout_sessions(merchant_code:, state: nil, payment_link_id: nil)
    query = { merchant_code: merchant_code }
    query[:state]           = state           if state
    query[:payment_link_id] = payment_link_id if payment_link_id
    get("/internal/merchants/#{merchant_code}/checkout-sessions?#{URI.encode_www_form(query.transform_keys(&:to_s))}")
  end

  # GET /internal/checkout-sessions/:id
  def get_checkout_session(public_id)
    get("/internal/checkout-sessions/#{public_id}")
  end

  # ── Payment links (P16) ───────────────────────────────────────────────────

  def list_payment_links(merchant_code:, starting_after: nil)
    query = { merchant_code: merchant_code }
    query[:starting_after] = starting_after if starting_after
    get("/internal/payment-links?#{URI.encode_www_form(query.transform_keys(&:to_s))}")
  end

  def create_payment_link(merchant_code:, **attrs)
    post("/internal/payment-links", attrs.merge(merchant_code: merchant_code))
  end

  def update_payment_link_layout(public_id, merchant_code:, layout:)
    patch("/internal/payment-links/#{public_id}/checkout-layout",
          { merchant_code: merchant_code, layout: layout })
  end

  # ── Merchant KYB approval (ops — UBO threshold enforced in Core) ─────────

  # POST /internal/merchants/:code/kyb-approve
  def approve_merchant_kyb(merchant_code, approved_by:)
    post("/internal/merchants/#{merchant_code}/kyb-approve",
         { approved_by: approved_by })
  end

  # ── KYB / Compliance (ops read + write) ───────────────────────────────────

  # GET /internal/merchants/:code/beneficial-owners
  def list_beneficial_owners(merchant_code)
    get("/internal/merchants/#{merchant_code}/beneficial-owners")
  end

  # POST /internal/merchants/:code/beneficial-owners
  # subject_ref: UUID (caller generates; will point to PII vault when KMS is wired)
  # role: "director" | "ubo" | "both"
  # ownership_bps: integer 0-10000 (100 bps = 1%)
  def add_beneficial_owner(merchant_code, subject_ref:, role:, ownership_bps:)
    post("/internal/merchants/#{merchant_code}/beneficial-owners", {
      subject_ref: subject_ref,
      role: role,
      ownership_bps: ownership_bps
    })
  end

  # GET /internal/merchants/:code/documents
  def list_kyb_documents(merchant_code)
    get("/internal/merchants/#{merchant_code}/documents")
  end

  # GET /internal/merchants/:code/screening-status
  def merchant_screening_status(merchant_code)
    get("/internal/merchants/#{merchant_code}/screening-status")
  end

  # ── Settlement dispatch approvals (SoD enforced in Core) ─────────────────

  # POST /internal/settlement-batches/:batch_id/approve-dispatch
  def approve_settlement_dispatch(batch_id, approved_by:)
    post("/internal/settlement-batches/#{batch_id}/approve-dispatch",
         { approved_by: approved_by })
  end

  # POST /internal/settlement-batches/:batch_id/reject-dispatch
  def reject_settlement_dispatch(batch_id, rejected_by:, reason: nil)
    post("/internal/settlement-batches/#{batch_id}/reject-dispatch",
         { rejected_by: rejected_by, reason: reason }.compact)
  end

  # GET /internal/merchants/:merchant_id/settlement-controls
  def get_settlement_controls(merchant_id)
    get("/internal/merchants/#{merchant_id}/settlement-controls")
  end

  # PUT /internal/merchants/:merchant_id/settlement-controls
  def upsert_settlement_controls(merchant_id, approval_threshold:, approver_user_codes:,
                                 settlement_frequency: nil, settlement_day: nil)
    put("/internal/merchants/#{merchant_id}/settlement-controls",
        {
          approval_threshold:   approval_threshold,
          approver_user_codes:  approver_user_codes,
          settlement_frequency: settlement_frequency,
          settlement_day:       settlement_day
        }.compact)
  end

  # ── Reconciliation (ops read-only) ────────────────────────────────────────

  # GET /internal/merchants/:merchant_id/reconciliation-breaks
  def list_reconciliation_breaks(merchant_code)
    get("/internal/merchants/#{merchant_code}/reconciliation-breaks")
  end

  # GET /internal/reconciliation-breaks (cross-merchant, ops only)
  def list_all_reconciliation_breaks
    get("/internal/reconciliation-breaks")
  end

  # GET /internal/reconciliation-breaks/:id
  def get_reconciliation_break(public_id)
    get("/internal/reconciliation-breaks/#{public_id}")
  end

  # POST /internal/reconciliation-breaks/:id/propose-adjustment
  def propose_reconciliation_adjustment(public_id, proposed_by:, amount:, direction:,
                                        resolution_code:, resolution_note: nil)
    post("/internal/reconciliation-breaks/#{public_id}/propose-adjustment", {
      proposed_by: proposed_by,
      amount: amount,
      direction: direction,
      resolution_code: resolution_code,
      resolution_note: resolution_note
    }.compact)
  end

  # ── Customers (P11) ───────────────────────────────────────────────────────

  # GET /internal/merchants/:code/customers
  def list_customers(merchant_code:, starting_after: nil)
    query = {}
    query = query.merge(starting_after: starting_after) if starting_after
    qs    = query.any? ? "?#{URI.encode_www_form(query.transform_keys(&:to_s))}" : ""
    get("/internal/merchants/#{merchant_code}/customers#{qs}")
  end

  # GET /internal/customers/:id
  def get_customer(public_id)
    get("/internal/customers/#{public_id}")
  end

  # ── Settlement batches (P9) ───────────────────────────────────────────────

  # GET /internal/merchants/:code/settlement-batches
  def list_settlement_batches(merchant_code:, starting_after: nil)
    query = {}
    query = query.merge(starting_after: starting_after) if starting_after
    qs    = query.any? ? "?#{URI.encode_www_form(query.transform_keys(&:to_s))}" : ""
    get("/internal/merchants/#{merchant_code}/settlement-batches#{qs}")
  end

  # GET /internal/settlement-batches-info/:id
  def get_settlement_batch(id)
    get("/internal/settlement-batches-info/#{id}")
  end

  # ── Pricing ───────────────────────────────────────────────────────────────

  # GET /internal/merchants/:code/pricing-plan
  def get_merchant_pricing_plan(merchant_code)
    get("/internal/merchants/#{merchant_code}/pricing-plan")
  end

  # GET /internal/merchants/:code/fee-invoices
  def list_fee_invoices(merchant_code:, limit: nil, offset: nil)
    query = {}
    query = query.merge("limit" => limit)   if limit
    query = query.merge("offset" => offset) if offset
    qs    = query.any? ? "?#{URI.encode_www_form(query)}" : ""
    get("/internal/merchants/#{merchant_code}/fee-invoices#{qs}")
  end



  # ── FX rates ──────────────────────────────────────────────────────────────

  # GET /internal/fx-rates
  def list_fx_rates
    get("/internal/fx-rates")
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

  def put(path, body)
    response = @conn.put(path, body, request_headers)
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Result.new(success?: false, error_code: "network_error", error_message: e.message)
  end

  def handle(response)
    if response.success?
      Result.new(success?: true, body: response.body)
    else
      body  = response.body
      error = body.is_a?(Hash) ? (body.dig("error") || {}) : {}
      Result.new(
        success?:      false,
        body:          body,
        error_code:    error["code"]    || response.status.to_s,
        error_message: error["message"] || "Core API error (#{response.status})"
      )
    end
  end

  def request_headers
    {
      "X-Service-Name"  => "portal",
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
