# frozen_string_literal: true

# Read model populated by Karafka consumers on webhook.endpoint.* events from Core.
class PortalWebhookEndpoint < ApplicationRecord
  self.primary_key = "endpoint_id"

  has_many :portal_webhook_deliveries, foreign_key: :endpoint_id, primary_key: :endpoint_id

  scope :for_mode, ->(mode) { where(mode: mode) }

  def events_count
    Array(subscribed_events).size
  end
end
