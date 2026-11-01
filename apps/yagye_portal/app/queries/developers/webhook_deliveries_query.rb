# frozen_string_literal: true

module Developers
  class WebhookDeliveriesQuery
    def initialize(relation = PortalWebhookDelivery.all)
      @relation = relation
    end

    DEFAULT_WINDOW_DAYS = 30

    def call(filters = {})
      scoped = @relation.includes(:portal_webhook_endpoint, :portal_merchant)
      scoped = scoped.where(merchant_code: Current.user.merchant_code) if Current.user&.merchant_code.present?
      scoped = scoped.where(merchant_code: filters[:merchant_code]) if filters[:merchant_code].present?
      scoped = scoped.where(endpoint_id: filters[:endpoint_id])    if filters[:endpoint_id].present?
      scoped = scoped.where(state: filters[:state])                if filters[:state].present?
      scoped = scoped.where(event_type: filters[:event_type])      if filters[:event_type].present?
      if filters[:from].present? || filters[:to].present?
        from = filters[:from].present? ? Time.zone.parse(filters[:from]).beginning_of_day : DEFAULT_WINDOW_DAYS.days.ago.beginning_of_day
        to   = filters[:to].present? ? Time.zone.parse(filters[:to]).end_of_day : Time.current
        scoped = scoped.where(last_applied_at: from..to)
      else
        scoped = scoped.where("last_applied_at >= ?", DEFAULT_WINDOW_DAYS.days.ago.beginning_of_day)
      end
      scoped.order(last_applied_at: :desc)
    end
  end
end
