# frozen_string_literal: true

# Read model populated by Karafka consumers on webhook.delivery.* events from Core.
# Aged out after 30 days — Core is the record of truth for delivery history.
class PortalWebhookDelivery < ApplicationRecord
  self.primary_key = "delivery_id"

  belongs_to :portal_webhook_endpoint, foreign_key: :endpoint_id, primary_key: :endpoint_id

  def success?
    response_status&.between?(200, 299)
  end

  def formatted_duration
    duration_ms ? "#{duration_ms} ms" : "—"
  end

  def formatted_headers
    return "{}" if request_headers.blank?
    JSON.pretty_generate(request_headers)
  end

  def formatted_request_body
    return "{}" if request_body.blank?
    JSON.pretty_generate(request_body)
  end

  def state_color
    case state
    when "delivered"  then "#16a34a"
    when "failed"     then "#f59e0b"
    when "exhausted"  then "#dc2626"
    when "delivering" then "#6366f1"
    else                   "#9ca3af"
    end
  end

  def short_event_id
    event_id&.first(12) || "—"
  end
end
