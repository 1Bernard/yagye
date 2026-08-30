# frozen_string_literal: true

class Dispute < ApplicationRecord
  self.table_name = "portal_disputes"

  REASONS = %w[fraud duplicate not_received unrecognised other].freeze
  STATUSES = %w[submitted under_review won lost closed].freeze

  OPEN_STATUSES  = %w[submitted under_review].freeze
  CLOSED_STATUSES = %w[won lost closed].freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }
  scope :recent,       -> { order(created_at: :desc) }
  scope :open,         -> { where(status: OPEN_STATUSES) }
  scope :won,          -> { where(status: "won") }
  scope :lost,         -> { where(status: "lost") }

  def formatted_amount
    major = amount_cents / 100.0
    format("%s %.2f", currency, major)
  end

  def masked_msisdn
    return "—" unless customer_msisdn.present?
    customer_msisdn.gsub(/(\d{3})\d{3}(\d+)/, '\1 *** \2')
  end

  def payment_reference
    self[:payment_reference].presence || core_payment_id&.first(12) || "—"
  end

  def open?
    OPEN_STATUSES.include?(status)
  end
end
