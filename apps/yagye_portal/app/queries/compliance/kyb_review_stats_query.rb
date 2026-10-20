# frozen_string_literal: true

module Compliance
  class KybReviewStatsQuery
    def initialize(scope = PortalMerchantApplication.all)
      @scope = scope
    end

    def call
      {
        pending:      @scope.where(status: "submitted").count,
        in_review:    @scope.where(status: "under_review").count,
        approved_30d: @scope.where(status: "approved").where("last_applied_at >= ?", 30.days.ago).count,
        rejected_30d: @scope.where(status: "rejected").where("last_applied_at >= ?", 30.days.ago).count
      }
    end
  end
end
