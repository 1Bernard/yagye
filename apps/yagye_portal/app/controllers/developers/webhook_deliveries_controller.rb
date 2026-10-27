# frozen_string_literal: true

module Developers
  class WebhookDeliveriesController < ApplicationController
    def index
      authorize :portal_webhook_delivery, :index?, policy_class: PortalWebhookDeliveryPolicy

      if current_user.internal_staff?
        @pagy, @deliveries = pagy(
          Developers::WebhookDeliveriesQuery.new(policy_scope(PortalWebhookDelivery)).call(filter_params),
          limit: 50
        )
        render Developers::DeliveriesIndexView.new(deliveries: @deliveries, pagy: @pagy)
      else
        redirect_to developers_path(tab: "deliveries")
      end
    end

    def show
      delivery = find_owned!(PortalWebhookDelivery)
      authorize delivery, :show?
      render Developers::DeliveryDrawerView.new(delivery: delivery)
    end

    private

    def filter_params
      params.permit(:state, :event_type, :endpoint_id, :merchant_code).to_h.symbolize_keys
    end

    public

    def retry
      delivery = find_owned!(PortalWebhookDelivery)
      authorize delivery, :show?
      result = CoreApiClient.new.retry_webhook_delivery(
        endpoint_id: delivery.endpoint_id,
        event_id:    delivery.event_id,
        event_type:  delivery.event_type,
        attempt:     delivery.attempt + 1,
        body:        delivery.request_body.is_a?(Hash) ? delivery.request_body.dig("data", "object") || delivery.request_body : {}
      )
      if result.success?
        redirect_to developers_path(tab: "logs"), notice: "Delivery queued for retry."
      else
        redirect_to developers_path(tab: "logs"), alert: result.error_message
      end
    end
  end
end
