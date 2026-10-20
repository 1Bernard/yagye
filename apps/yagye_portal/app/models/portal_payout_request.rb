# frozen_string_literal: true

class PortalPayoutRequest < ApplicationRecord
  include MoneyDisplayable

  self.primary_key = "request_code"

  STATES = %w[pending approved rejected].freeze

  before_create :generate_request_code

  validates :merchant_code, :requested_by, :reason, :state, presence: true
  validates :state, inclusion: { in: STATES }
  validates :reason, length: { minimum: 10, maximum: 500 }

  scope :for_merchant,    ->(code) { where(merchant_code: code) }
  scope :pending_review,  -> { where(state: "pending") }
  scope :recent,          -> { order(created_at: :desc) }

  def formatted_amount
    return "Full unsettled balance" if amount.nil?

    format_minor_units(amount, currency)
  end

  def pending?  = state == "pending"
  def approved? = state == "approved"
  def rejected? = state == "rejected"

  private

  def generate_request_code
    self.request_code = SecureRandom.uuid if request_code.blank?
  end
end
