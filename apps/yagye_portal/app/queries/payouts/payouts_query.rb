# frozen_string_literal: true

module Payouts
  class PayoutsQuery
    def initialize(relation = PortalPayout.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.where(state: filters[:state])                           if filters[:state].present?
      scoped = scoped.where("created_at >= ?", filters[:from])                if filters[:from].present?
      scoped = scoped.where("created_at <= ?", filters[:to])                  if filters[:to].present?
      scoped.order(last_applied_at: :desc)
    end
  end
end
