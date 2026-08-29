# frozen_string_literal: true

module Developers
  class WebhookDeliveriesQuery
    def initialize(relation = PortalWebhookDelivery.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation.includes(:portal_webhook_endpoint)
      scoped = scoped.where(merchant_code: Current.merchant&.merchant_code) if Current.merchant.present?
      scoped = scoped.where(endpoint_id: filters[:endpoint_id]) if filters[:endpoint_id].present?
      scoped = scoped.where(state: filters[:state])             if filters[:state].present?
      scoped = scoped.where(event_type: filters[:event_type])   if filters[:event_type].present?
      scoped.order(last_applied_at: :desc)
    end
  end
end
