# frozen_string_literal: true

module Acl
  # Translates a raw Core payment event payload into Portal's model language.
  #
  # This is the Anti-Corruption Layer (ACL) between Core's domain and Portal's.
  # All field name differences between Core and Portal are resolved here — nowhere else.
  #
  # Core field  → Portal column   Reason for difference
  # ----------    -------------   ---------------------
  # state       → status          Core: state-machine term. Portal: UI-facing term.
  # method      → payment_method  Portal disambiguates from Ruby's Object#method.
  class CorePaymentEvent
    def initialize(payload)
      @p = payload
    end

    def valid? = @p["public_id"].present?

    # ── Identity ──────────────────────────────────────────────────────────────

    def public_id     = @p["public_id"]
    def merchant_code = @p["merchant_code"]
    def event_type    = @p["event_type"]

    # ── Translations (Core name ≠ Portal column name) ─────────────────────────

    # Core state-machine names → Portal UI-facing status labels.
    # "succeeded" → "paid" is the canonical example: Core records the fact of
    # authorisation, Portal shows the customer-facing outcome.
    STATE_MAP = {
      "created"          => "created",
      "processing"       => "processing",
      "requires_action"  => "requires_action",
      "authorised"       => "processing",
      "succeeded"        => "paid",
      "failed"           => "failed",
      "cancelled"        => "cancelled",
      "indeterminate"    => "indeterminate",
      "disputed"         => "disputed",
      "refunded"         => "refunded",
      "chargebacked"     => "refunded"
    }.freeze

    def status         = STATE_MAP.fetch(@p["state"].to_s, @p["state"].to_s)
    def payment_method = @p["method"]

    # ── Direct mappings ───────────────────────────────────────────────────────

    def amount          = @p["amount"].to_i
    def currency        = @p["currency"].presence || "GHS"
    def reference       = @p["merchant_reference"]
    def description     = @p["description"]
    def mode            = @p["mode"]
    def provider        = @p["provider"]
    def customer_msisdn = @p["customer_msisdn"]
    def customer_email  = @p["customer_email"]
    def metadata        = @p["metadata"] || {}
    def paid_at         = @p["paid_at"]
    def settled_at      = @p["settled_at"]
  end
end
