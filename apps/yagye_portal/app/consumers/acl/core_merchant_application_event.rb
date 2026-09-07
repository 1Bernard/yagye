# frozen_string_literal: true

module Acl
  # Translates a raw Core merchant application event payload into Portal's model language.
  #
  # Core field        → Portal field        Reason
  # ----------------    -----------------   -------
  # public_id         → application_code   Portal uses a named identifier, not generic public_id
  # merchant_public_id→ merchant_code       Core uses a verbose key; Portal normalises to merchant_code
  # email             → submitted_by_email  Portal disambiguates — the application may carry multiple emails
  class CoreMerchantApplicationEvent
    def initialize(payload)
      @p = payload
    end

    def valid?            = application_code.present?

    def event_type        = @p["event_type"]
    def application_code  = @p["public_id"]
    def aggregate_version = @p["aggregate_version"].to_i
    def event_id          = @p["event_id"].presence || @p["public_id"]

    def legal_name         = @p["legal_name"]
    def trading_name       = @p["trading_name"]
    def country            = @p["country"]
    def industry           = @p["industry"]
    def employee_range     = @p["employee_range"]
    def submitted_by_email = @p["email"]

    def reviewed_by  = @p["reviewed_by"]

    def approved_by  = @p["approved_by"]
    def merchant_code = @p["merchant_public_id"]

    def rejected_reason = @p["reason"]
  end
end
