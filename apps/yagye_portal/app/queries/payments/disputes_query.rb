# frozen_string_literal: true

module Payments
  class DisputesQuery
    TAB_STATUSES = {
      "open" => Dispute::OPEN_STATUSES,
      "won"  => %w[won],
      "lost" => %w[lost]
    }.freeze

    def initialize(relation = Dispute.all)
      @relation = relation
    end

    def call(filters = {})
      scope = @relation.recent
      scope = scope.where(status: TAB_STATUSES[filters[:tab]]) if TAB_STATUSES.key?(filters[:tab])
      scope = scope.where("reference ILIKE ? OR payment_reference ILIKE ?",
                          "%#{sanitize(filters[:query])}%",
                          "%#{sanitize(filters[:query])}%") if filters[:query].present?
      scope = scope.where(reason: filters[:reason]) if filters[:reason].present?
      scope = scope.where("opened_at >= ?", filters[:date_from]) if filters[:date_from].present?
      scope = scope.where("opened_at <= ?", filters[:date_to])   if filters[:date_to].present?
      scope
    end

    private

    def sanitize(value)
      ActiveRecord::Base.sanitize_sql_like(value.to_s)
    end
  end
end
