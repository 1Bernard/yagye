# frozen_string_literal: true

module Developers
  class ApiKeysController < ApplicationController
    def index
      authorize :developers, :index?

      @tab      = params[:tab].presence_in(%w[api_keys webhooks logs]) || "api_keys"
      key_scope = policy_scope(PortalApiKey)
      wh_scope  = policy_scope(PortalWebhookEndpoint)

      @api_keys = Developers::ApiKeysQuery.new(key_scope).call
      @webhooks = Developers::WebhookEndpointsQuery.new(wh_scope).call
    end
  end
end
