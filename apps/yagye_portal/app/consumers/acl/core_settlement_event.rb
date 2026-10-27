# frozen_string_literal: true

module Acl
  # Translates a raw Core settlement event payload into Portal's model language.
  #
  # Core field      → Portal column          Reason
  # -----------       --------------------   -------
  # net_amount      → expected_net           "expected_net" clarifies this is the pre-confirmed figure
  # payment_count   → item_count             Portal uses item_count to stay method-agnostic
  # timestamp       → last_applied_at        Portal convention for when the row was last touched
  class CoreSettlementEvent
    def initialize(payload)
      @p = payload
    end

    def valid?           = @p["settlement_code"].present?

    def settlement_code  = @p["settlement_code"]
    def merchant_code    = @p["merchant_code"]
    def provider_code    = @p["provider_code"]
    def mode             = @p["mode"] || "test"
    def aggregate_version = @p["aggregate_version"].to_i
    def state            = @p["state"]
    def currency         = @p["currency"] || "GHS"
    def period_start     = @p["period_start"]
    def period_end       = @p["period_end"]
    def expected_net     = (@p["expected_net"] || @p["net_amount"]).to_i
    def gross_amount     = @p["gross_amount"]
    def platform_fees    = @p["platform_fees"]
    def reported_net     = @p["reported_net"]
    def variance         = @p["variance"]
    def value_date       = @p["value_date"]
    def item_count       = (@p["item_count"] || @p["payment_count"])&.to_i
    def bank_dispatch_ref         = @p["bank_dispatch_ref"]
    def bank_dispatched_at        = @p["bank_dispatched_at"]
    def dispatch_approved_by      = @p["dispatch_approved_by"]
    def dispatch_rejected_by      = @p["dispatch_rejected_by"]
    def dispatch_rejection_reason = @p["dispatch_rejection_reason"]
    def event_id         = @p["event_id"].to_s
    def last_applied_at  = @p["timestamp"] || Time.current
  end
end
