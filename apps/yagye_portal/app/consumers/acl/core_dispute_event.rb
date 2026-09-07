# frozen_string_literal: true

module Acl
  # Translates a raw Core dispute event payload into Portal's model language.
  #
  # Core field  → Portal column     Reason
  # ----------    ----------------  -------
  # dispute_id  → core_dispute_id   Portal prefixes Core IDs to make the foreign-key origin explicit
  # payment_id  → core_payment_id   Same convention
  # amount      → amount            No translation needed; both use minor units
  class CoreDisputeEvent
    def initialize(payload)
      @p = payload
    end

    def valid? = @p["dispute_id"].present?

    def core_dispute_id  = @p["dispute_id"]
    def core_payment_id  = @p["payment_id"]
    def merchant_code    = @p["merchant_code"]
    def payment_reference = @p["payment_reference"]
    def reference        = @p["reference"]
    def amount           = @p["amount"].to_i
    def currency         = @p["currency"].presence || "GHS"
    def reason           = @p["reason"]
    def status           = @p["status"]
    def customer_msisdn  = @p["customer_msisdn"]
    def network_deadline = @p["network_deadline"]
    def opened_at        = @p["opened_at"]
    def resolved_at      = @p["resolved_at"]
    def event_id         = @p["event_id"].to_s
  end
end
