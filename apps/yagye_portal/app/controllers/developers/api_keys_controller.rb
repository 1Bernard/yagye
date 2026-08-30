# frozen_string_literal: true

module Developers
  class ApiKeysController < ApplicationController
    def index
      authorize :developers, :index?

      tab        = params[:tab].presence_in(%w[api_keys webhooks logs]) || "api_keys"
      api_keys   = Developers::ApiKeysQuery.new(policy_scope(PortalApiKey)).call
      webhooks   = Developers::WebhookEndpointsQuery.new(policy_scope(PortalWebhookEndpoint)).call
      pagy       = nil
      deliveries = []

      if tab == "logs"
        pagy, deliveries = pagy(
          Developers::WebhookDeliveriesQuery.new(policy_scope(PortalWebhookDelivery))
            .call(endpoint_id: params[:endpoint_id], state: params[:state]),
          limit: 25
        )
      end

      render Developers::IndexView.new(
        tab: tab, api_keys: api_keys, webhooks: webhooks,
        deliveries: deliveries, pagy: pagy
      )
    end

    def create
      authorize :developers, :manage_keys?
      result = CoreApiClient.new.generate_api_key(
        merchant_code: current_user.merchant_code,
        label:         key_params[:label],
        mode:          key_params[:mode].presence_in(%w[live test]) || "test",
        scopes:        Array(key_params[:scopes]),
        created_by:    current_user.email
      )
      if result.success?
        redirect_to developers_path(tab: "api_keys"),
                    notice: "API key created. Copy it now — it won't be shown again."
      else
        redirect_to developers_path(tab: "api_keys"), alert: result.error_message
      end
    end

    def destroy
      authorize :developers, :manage_keys?
      result = CoreApiClient.new.revoke_api_key(params[:key_id], revoked_by: current_user.email)
      if result.success?
        redirect_to developers_path(tab: "api_keys"), notice: "API key revoked."
      else
        redirect_to developers_path(tab: "api_keys"), alert: result.error_message
      end
    end

    private

    def key_params
      params.permit(:label, :mode, scopes: [])
    end
  end
end
