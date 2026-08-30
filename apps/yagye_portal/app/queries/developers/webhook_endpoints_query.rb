# frozen_string_literal: true

module Developers
  class WebhookEndpointsQuery
    def initialize(relation = PortalWebhookEndpoint.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.where(mode: Current.mode) if Current.mode.present?
      scoped = scoped.where(active: true)  if filters[:active] == "true"
      scoped = scoped.where(active: false) if filters[:active] == "false"
      scoped.recent.limit(200)
    end
  end
end
