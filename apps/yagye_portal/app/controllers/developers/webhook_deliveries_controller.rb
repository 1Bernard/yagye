# frozen_string_literal: true

module Developers
  class WebhookDeliveriesController < ApplicationController
    def index
      authorize :developers, :index?

      @endpoint_id   = params[:endpoint_id]
      @state_filter  = params[:state]
      @event_filter  = params[:event_type]

      deliveries = Developers::WebhookDeliveriesQuery.new(policy_scope(PortalWebhookDelivery))
                     .call(endpoint_id: @endpoint_id, state: @state_filter, event_type: @event_filter)

      @pagy, @deliveries = pagy(deliveries, limit: 25)
    end

    def show
      delivery = policy_scope(PortalWebhookDelivery).find(params[:id])
      authorize delivery, :show?
      render Developers::DeliveryDrawerPage.new(delivery: delivery)
    end
  end
end
