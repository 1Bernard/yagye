# frozen_string_literal: true

module Developers
  class ApiKeysQuery
    def initialize(relation = PortalApiKey.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.where(mode: Current.mode) if Current.mode.present?
      scoped = scoped.where(kind: filters[:kind]) if filters[:kind].present?
      scoped = case filters[:status]
      when "active"  then scoped.active
      when "revoked" then scoped.revoked
      else scoped
      end
      scoped.order(created_at: :desc).limit(200)
    end
  end
end
