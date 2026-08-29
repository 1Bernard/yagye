# frozen_string_literal: true

module Developers
  class ApiKeysController < ApplicationController
    def index
      authorize :developers, :index?

      tab       = params[:tab].presence_in(%w[api_keys webhooks logs]) || "api_keys"
      api_keys  = Developers::ApiKeysQuery.new(policy_scope(PortalApiKey)).call
      webhooks  = Developers::WebhookEndpointsQuery.new(policy_scope(PortalWebhookEndpoint)).call
      pagy      = nil
      deliveries = []

      if tab == "logs"
        pagy, deliveries = pagy(
          Developers::WebhookDeliveriesQuery.new(policy_scope(PortalWebhookDelivery))
            .call(endpoint_id: params[:endpoint_id], state: params[:state]),
          limit: 25
        )
      end

      render Developers::IndexPage.new(
        tab: tab, api_keys: api_keys, webhooks: webhooks,
        deliveries: deliveries, pagy: pagy
      )
    end
  end
end
