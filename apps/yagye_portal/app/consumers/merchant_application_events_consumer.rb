class MerchantApplicationEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert_application(message.payload)
    rescue StandardError => e
      Rails.logger.error("MerchantApplicationEventsConsumer: failed to process message — #{e.message}")
    end
  end

  private

  def upsert_application(payload)
    event_type = payload["event_type"]
    application_code = payload["public_id"]
    return unless application_code.present?

    record = PortalMerchantApplication.find_or_initialize_by(application_code: application_code)
    record.aggregate_version = [ record.aggregate_version.to_i, payload["aggregate_version"].to_i ].max
    record.last_event_id     = payload["event_id"] || payload["public_id"]
    record.last_applied_at   = Time.current

    case event_type
    when "merchant.application.submitted"
      record.status            = "submitted"
      record.legal_name        = payload["legal_name"]
      record.trading_name      = payload["trading_name"]
      record.country           = payload["country"]
      record.industry          = payload["industry"]
      record.employee_range    = payload["employee_range"]
      record.submitted_by_email = payload["email"]
    when "merchant.application.review_started"
      record.status      = "under_review"
      record.reviewed_by = payload["reviewed_by"]
    when "merchant.application.approved"
      record.status        = "approved"
      record.approved_by   = payload["approved_by"]
      record.merchant_code = payload["merchant_public_id"]
    when "merchant.application.rejected"
      record.status           = "rejected"
      record.rejected_reason  = payload["reason"]
    end

    record.save!
  end
end
