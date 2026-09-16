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
  end
end
