# frozen_string_literal: true

class MerchantApplicationEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event = Acl::CoreMerchantApplicationEvent.new(message.payload)
      next unless event.valid?

      if event.event_type == "merchant.approved"
        activate_live_mode(event)
      else
        upsert_application(event)
      end
    end
  end

  private

  def upsert_application(event)
    record = PortalMerchantApplication.find_or_initialize_by(application_code: event.application_code)
    record.aggregate_version = [ record.aggregate_version.to_i, event.aggregate_version ].max
    record.last_event_id     = event.event_id
    record.last_applied_at   = Time.current

    case event.event_type
    when "merchant.application.submitted"
      record.status             = "submitted"
      record.legal_name         = event.legal_name
      record.trading_name       = event.trading_name
      record.country            = event.country
      record.industry           = event.industry
      record.employee_range     = event.employee_range
      record.submitted_by_email = event.submitted_by_email
    when "merchant.application.review_started"
      record.status      = "under_review"
      record.reviewed_by = event.reviewed_by
    when "merchant.application.approved"
      record.status        = "approved"
      record.approved_by   = event.approved_by
      record.merchant_code = event.merchant_code
    when "merchant.application.rejected"
      record.status          = "rejected"
      record.rejected_reason = event.rejected_reason
    else
      return
    end

    record.save!
    notify_kyb_status(record)
  end

  def notify_kyb_status(record)
    return if record.merchant_code.blank?

    status_label = record.status.tr("_", " ").capitalize
    Notifications::DeliveryService.deliver(
      merchant_code: record.merchant_code,
      event_type:    "kyb_status",
      title:         "KYB status update",
      body:          "Your application status is now: #{status_label}",
      link:          "/settings?tab=verification",
      metadata:      { application_code: record.application_code, status: record.status }
    )
  rescue StandardError => e
    Rails.logger.warn("[MerchantApplicationEventsConsumer] notify failed: #{e.message}")
  end

  def activate_live_mode(event)
    merchant_code = event.merchant_code
    return if merchant_code.blank?

    PortalMerchant
      .find_or_initialize_by(merchant_code: merchant_code)
      .tap do |m|
        m.status          = "approved"
        m.onboarding_state = "approved"
        m.live_mode_enabled = true
        m.last_event_id   = event.event_id
        m.last_applied_at = Time.current
      end
      .save!
  end
end
