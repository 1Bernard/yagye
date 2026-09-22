# frozen_string_literal: true

module Developers
  class WebhookDeliveriesController < ApplicationController
    def index
      redirect_to developers_path(tab: "deliveries")
    end

    def show
      delivery = decode_id(PortalWebhookDelivery)
      authorize delivery, :show?
      render Developers::DeliveryDrawerView.new(delivery: delivery)
    end

    def retry
      delivery = decode_id(PortalWebhookDelivery)
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
