# frozen_string_literal: true

module Payments
  # Read-only query object for the payments list.
  # Receives a policy-scoped relation from the controller so tenancy is
  # already applied before any filter runs.
  class TransactionsQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.by_status(filters[:status])     if filters[:status].present?
      scoped = scoped.search_ref(filters[:q])         if filters[:q].present?
      scoped = scoped.where(provider: filters[:provider]) if filters[:provider].present?
      scoped = filter_date(scoped, :from, filters[:from])
      scoped = filter_date(scoped, :to,   filters[:to])
      scoped.recent
    end

    private

    def filter_date(scope, bound, value)
      return scope if value.blank?
      date = Date.parse(value)
      bound == :from ? scope.where("created_at >= ?", date.beginning_of_day)
                     : scope.where("created_at <= ?", date.end_of_day)
    rescue ArgumentError
      scope
    end
  end
end
