# frozen_string_literal: true

class PortalPayoutRequest < ApplicationRecord
  STATES = %w[pending approved rejected].freeze

  validates :merchant_code, :requested_by, :reason, :state, presence: true
  validates :state, inclusion: { in: STATES }
  validates :reason, length: { minimum: 10, maximum: 500 }

  scope :for_merchant,    ->(code) { where(merchant_code: code) }
  scope :pending_review,  -> { where(state: "pending") }
  scope :recent,          -> { order(created_at: :desc) }

  def formatted_amount
    return "Full unsettled balance" if amount_cents.nil?

    "#{currency} #{"%.2f" % (amount_cents / 100.0)}"
  end

  def pending?  = state == "pending"
  def approved? = state == "approved"
  def rejected? = state == "rejected"
end
