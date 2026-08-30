# frozen_string_literal: true

module Payments
  # Read-only query object for the payments list.
  # Receives a policy-scoped relation from the controller so tenancy is
  # already applied before any filter runs.
  class TransactionsQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    DEFAULT_WINDOW_DAYS = 30

    def call(filters = {})
      scoped = @relation
      scoped = scoped.where(mode: Current.mode)            if Current.mode.present?
      scoped = scoped.by_status(filters[:status])         if filters[:status].present?
      scoped = scoped.search_ref(filters[:q])             if filters[:q].present?
      scoped = scoped.where(provider: filters[:provider]) if filters[:provider].present?
      scoped = apply_date_window(scoped, filters)
      scoped.recent
    end

    private

    def apply_date_window(scope, filters)
      from_scope = filter_date(scope, :from, filters[:from])
      to_scope   = filter_date(from_scope, :to, filters[:to])

      # Enforce a default floor so the query is always bounded.
      # Ops users can widen this via the date picker; we never scan all records silently.
      if filters[:from].blank? && filters[:to].blank?
        to_scope.where("created_at >= ?", DEFAULT_WINDOW_DAYS.days.ago.beginning_of_day)
      else
        to_scope
      end
    end

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
