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
      scoped.recent
    end
  end
end
