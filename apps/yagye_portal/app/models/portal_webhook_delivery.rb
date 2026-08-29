# frozen_string_literal: true

# Read model populated by Karafka consumers on webhook.delivery.* events from Core.
# Aged out after 30 days — Core is the record of truth for delivery history.
class PortalWebhookDelivery < ApplicationRecord
  self.primary_key = "delivery_id"

  belongs_to :portal_webhook_endpoint, foreign_key: :endpoint_id, primary_key: :endpoint_id
end
