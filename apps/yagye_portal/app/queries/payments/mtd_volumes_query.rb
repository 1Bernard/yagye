# frozen_string_literal: true

module Payments
  class MtdVolumesQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call(merchant_codes:)
      codes = Array(merchant_codes).compact.uniq
      return {} if codes.empty?

      @relation
        .where(merchant_code: codes, status: "paid")
        .where("created_at >= ?", Time.current.beginning_of_month)
        .group(:merchant_code)
        .sum(:amount)
    end
  end
end
