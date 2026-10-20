# frozen_string_literal: true

module Acl
  # Translates a raw Core payout event payload into Portal's model language.
  #
  # Core field  → Portal column   Reason
  # ----------    -------------   -------
  # public_id   → payout_code     Portal uses payout_code as the stable identifier
  # timestamp   → last_applied_at Portal convention for when the row was last touched
  class CorePayoutEvent
    def initialize(payload)
      @p = payload
    end

    def valid?           = payout_code.present?

    def payout_code      = @p["payout_code"] || @p["public_id"]
    def merchant_code    = @p["merchant_code"]
    def mode             = @p["mode"] || "test"
    def aggregate_version = @p["aggregate_version"].to_i
    def state            = @p["state"]
    def amount           = @p["amount"].to_i
    def currency         = @p["currency"] || "GHS"
    def destination_type        = @p["destination_type"]
    def destination_fingerprint = @p["destination_fingerprint"]
    def scheduled_for    = @p["scheduled_for"]
    def failure_code     = @p["failure_code"]
    def event_id         = @p["event_id"].to_s
    def last_applied_at  = @p["timestamp"] || Time.current
  end
end
