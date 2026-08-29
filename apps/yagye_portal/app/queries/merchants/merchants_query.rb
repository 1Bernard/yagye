# frozen_string_literal: true

module Merchants
  # Ops-facing query over PortalMerchantApplication.
  # When Core's merchant read-model is replicated to the portal DB,
  # swap @relation for that model and update the filter columns.
  class MerchantsQuery
    def initialize(relation = PortalMerchantApplication.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.by_status(filters[:status]) if filters[:status].present?
      scoped = scoped.where(country: filters[:country]) if filters[:country].present?
      if filters[:q].present?
        q      = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q])}%"
        scoped = scoped.where("legal_name ILIKE ? OR merchant_code ILIKE ?", q, q)
      end
      scoped.recent
    end
  end
end
