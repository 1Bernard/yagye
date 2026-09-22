# frozen_string_literal: true

module Developers
  class ApiKeysController < ApplicationController
    def index
      authorize :developers, :index?

      tab        = params[:tab].presence_in(%w[quickstart api_keys webhooks logs reference]) || "quickstart"
      api_keys   = Developers::ApiKeysQuery.new(policy_scope(PortalApiKey)).call
      webhooks   = Developers::WebhookEndpointsQuery.new(policy_scope(PortalWebhookEndpoint)).call
      pagy       = nil
      deliveries = []
      reveal_key            = flash[:reveal_key]
      reveal_webhook_secret = flash[:reveal_webhook_secret]
      spec                  = {}

      if tab == "logs"
        pagy, deliveries = pagy(
          Developers::WebhookDeliveriesQuery.new(policy_scope(PortalWebhookDelivery))
            .call(endpoint_id: params[:endpoint_id], state: params[:state]),
          limit: 25
        )
      elsif tab == "reference"
        spec = CoreApiClient.new.openapi_spec
        if spec.empty?
          cache = Rails.root.join("config/openapi_spec_cache.json")
          spec  = JSON.parse(File.read(cache)) rescue {}
        end
      end

      render Developers::IndexView.new(
        tab: tab, api_keys: api_keys, webhooks: webhooks,
        deliveries: deliveries, pagy: pagy, reveal_key: reveal_key,
        reveal_webhook_secret: reveal_webhook_secret,
        openapi_spec: spec
      )
    end

    def new
      authorize :developers, :manage_keys?
      render Developers::KeyFormView.new(mode: current_portal_mode)
    end

    def create
      authorize :developers, :manage_keys?
      result = CoreApiClient.new.generate_api_key(
        merchant_code: current_user.merchant_code,
        label:         key_params[:label],
        mode:          key_params[:mode].presence_in(%w[live test]) || "test",
        scopes:        Array(key_params[:scopes]),
        created_by:    current_user.user_code
      )
      if result.success?
        upsert_api_key(result.body)
        flash[:reveal_key] = result.body["key"]
        redirect_to developers_url(tab: "api_keys")
      else
        redirect_to developers_url(tab: "api_keys"), alert: result.error_message
      end
    end

    def destroy
      authorize :developers, :manage_keys?
      result = CoreApiClient.new.revoke_api_key(params[:key_id], revoked_by: current_user.user_code)
      if result.success?
        PortalApiKey.find_by(key_id: params[:key_id])
                    &.update(revoked_at: Time.current)
        redirect_to developers_path(tab: "api_keys"), notice: "API key revoked."
      else
        redirect_to developers_path(tab: "api_keys"), alert: result.error_message
      end
    end

    private

    def current_portal_mode
      session[:portal_mode] || "test"
    end

    def key_params
      params.permit(:label, :mode, scopes: [])
    end

    def upsert_api_key(body)
      PortalApiKey.upsert(
        {
          key_id:          body["id"],
          merchant_code:   current_user.merchant_code,
          label:           body["label"] || "",
          key_prefix:      body["key_prefix"] || "",
          kind:            body["kind"] || "secret",
          mode:            body["mode"] || "test",
          scopes:          body["scopes"] || [],
          created_by:      body["created_by"],
          last_event_id:   "",
          last_applied_at: Time.current
        },
        unique_by: :key_id,
        update_only: %i[label key_prefix kind mode scopes created_by last_applied_at]
      )
    end
  end
end
