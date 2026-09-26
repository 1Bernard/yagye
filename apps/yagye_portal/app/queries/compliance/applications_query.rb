# frozen_string_literal: true

module Compliance
  # KYB review queue query. Maps UI tab names to the DB status values
  # stored by the PortalMerchantApplication aggregate.
  class ApplicationsQuery
    TAB_STATUSES = {
      "pending"   => %w[submitted],
      "in_review" => %w[under_review],
      "approved"  => %w[approved],
      "rejected"  => %w[rejected]
    }.freeze

    def initialize(relation = PortalMerchantApplication.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      tab    = filters[:tab].to_s
      scoped = scoped.where(status: TAB_STATUSES[tab]) if TAB_STATUSES.key?(tab)
      if filters[:q].present?
        q      = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q])}%"
        scoped = scoped.where("legal_name ILIKE ? OR merchant_code ILIKE ?", q, q)
      end
      scoped = scoped.where("last_applied_at >= ?", filters[:from])        if filters[:from].present?
      scoped = scoped.where("last_applied_at <= ?", filters[:to])          if filters[:to].present?
      scoped = scoped.where(reviewed_by: nil)                              if filters[:reviewer] == "unassigned"
      scoped = scoped.where(reviewed_by: filters[:current_user_code])      if filters[:reviewer] == "mine"
      scoped.recent
    end
  end
end
