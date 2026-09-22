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
        flash[:reveal_webhook_secret] = result.body["signing_secret"]
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint added."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def edit
      authorize :developers, :manage_webhooks?
      endpoint = PortalWebhookEndpoint.kept.find_by!(endpoint_id: params[:endpoint_id])
      render Developers::WebhookFormView.new(mode: endpoint.mode, endpoint: endpoint)
    end

    def update
      authorize :developers, :manage_webhooks?
      endpoint = PortalWebhookEndpoint.kept.find_by!(endpoint_id: params[:endpoint_id])
      result = CoreApiClient.new.update_webhook_endpoint(
        merchant_code:     current_user.merchant_code,
        endpoint_id:       params[:endpoint_id],
        url:               webhook_params[:url].presence || endpoint.url,
        subscribed_events: Array(webhook_params[:subscribed_events]),
        active:            endpoint.active
      )
      if result.success?
        endpoint.update!(
          url:               result.body["url"],
          subscribed_events: Array(result.body["subscribed_events"]),
          last_applied_at:   Time.current
        )
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint updated."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def toggle_active
      authorize :developers, :manage_webhooks?
      endpoint = PortalWebhookEndpoint.kept.find_by!(endpoint_id: params[:endpoint_id])
      new_active = !endpoint.active

      result = CoreApiClient.new.update_webhook_endpoint(
        merchant_code:     current_user.merchant_code,
        endpoint_id:       params[:endpoint_id],
        url:               endpoint.url,
        subscribed_events: Array(endpoint.subscribed_events),
        active:            new_active
      )

      if result.success?
        endpoint.update!(active: new_active, last_applied_at: Time.current)
        msg = new_active ? "Webhook endpoint re-enabled." : "Webhook endpoint disabled."
        redirect_to developers_path(tab: "webhooks"), notice: msg
      elsif result.error_code == "endpoint_cooldown"
        retry_after = result.body.dig("error", "retry_after")
        readable    = retry_after ? " You can try again after #{Time.parse(retry_after).strftime('%H:%M UTC on %d %b')}." : ""
        redirect_to developers_path(tab: "webhooks"),
                    alert: "This endpoint was auto-suspended due to repeated delivery failures.#{readable}"
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def destroy
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.remove_webhook_endpoint(
        merchant_code: current_user.merchant_code,
        endpoint_id:   params[:endpoint_id]
      )
      # Treat 404 as success — endpoint is already absent from Core, so removing
      # the Portal record is always safe (idempotent delete).
      if result.success? || result.error_code == "not_found"
        PortalWebhookEndpoint.find_by(endpoint_id: params[:endpoint_id])&.soft_delete!
        redirect_to developers_path(tab: "webhooks"), notice: "Webhook endpoint removed."
      else
        redirect_to developers_path(tab: "webhooks"), alert: result.error_message
      end
    end

    def test
      authorize :developers, :manage_webhooks?
      result = CoreApiClient.new.test_webhook_endpoint(
        merchant_code: current_user.merchant_code,
        endpoint_id:   params[:endpoint_id]
      )
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
          last_applied_at:      Time.current,
          deleted_at:           nil
        },
        unique_by: :endpoint_id,
        update_only: %i[url mode active subscribed_events consecutive_failures last_applied_at deleted_at]
      )
    end
  end
end
