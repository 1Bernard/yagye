# frozen_string_literal: true

module Developers
  class WebhooksController < ApplicationController
    def create
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.add_webhook_endpoint(
        merchant_code:     current_user.merchant_code,
        url:               webhook_params[:url],
        subscribed_events: Array(webhook_params[:subscribed_events]),
        mode:              current_portal_mode
      )
      if result.success?
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint added."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def destroy
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.remove_webhook_endpoint(params[:endpoint_id])
      if result.success?
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint removed."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def test
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.test_webhook_endpoint(params[:endpoint_id])
      if result.success?
        redirect_to developers_path(tab: "webhooks"), notice: "Test event sent."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    private

    def webhook_params
      params.permit(:url, subscribed_events: [])
    end

    def current_portal_mode
      session[:portal_mode] || "test"
    end
  end
end
