# frozen_string_literal: true

module Developers
  class WebhooksController < ApplicationController
    def new
      authorize :developers, :manage_webhooks?
      render Developers::WebhookFormView.new(mode: current_portal_mode)
    end

    def create
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.add_webhook_endpoint(
        merchant_code:     current_user.merchant_code,
        url:               webhook_params[:url],
        subscribed_events: Array(webhook_params[:subscribed_events]),
        mode:              current_portal_mode
      )
      if result.success?
        upsert_endpoint(result.body)
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint added."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def destroy
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.remove_webhook_endpoint(params[:endpoint_id])
      if result.success?
        PortalWebhookEndpoint.find_by(endpoint_id: params[:endpoint_id])&.destroy
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

    def upsert_endpoint(body)
      PortalWebhookEndpoint.upsert(
        {
          endpoint_id:          body["id"],
          merchant_code:        current_user.merchant_code,
          url:                  body["url"],
          mode:                 body["mode"] || "test",
          active:               body["active"] != false,
          subscribed_events:    Array(body["subscribed_events"]),
          consecutive_failures: 0,
          last_event_id:        "",
          last_applied_at:      Time.current
        },
        unique_by: :endpoint_id,
        update_only: %i[url mode active subscribed_events consecutive_failures last_applied_at]
      )
    end
  end
end
