# frozen_string_literal: true

class PortalPayout < ApplicationRecord
  self.table_name  = "portal_payouts"
  self.primary_key = "payout_code"

  STATES = %w[scheduled validating reserving submitted paid returned failed cancelled].freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }
  scope :in_flight,    -> { where(state: %w[scheduled validating reserving submitted]) }

  def formatted_amount
    "#{currency} #{"%.2f" % (amount / 100.0)}"
  end

  def created_at = last_applied_at
end
