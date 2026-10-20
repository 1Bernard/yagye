# frozen_string_literal: true

class Dispute < ApplicationRecord
  include MoneyDisplayable
  self.table_name = "portal_disputes"
  def self.policy_class = DisputesPolicy

  REASONS = %w[fraud duplicate not_received unrecognised unauthorized_transfer non_delivery other].freeze
  STATUSES = %w[submitted under_review won lost closed].freeze

  OPEN_STATUSES  = %w[submitted under_review].freeze
  CLOSED_STATUSES = %w[won lost closed].freeze

  has_many_attached :evidence_files
  has_many_attached :evidence_draft_files

  scope :for_merchant, ->(code) { where(merchant_code: code) }
  scope :recent,       -> { order(created_at: :desc) }
  scope :open,         -> { where(status: OPEN_STATUSES) }
  scope :won,          -> { where(status: "won") }
  scope :lost,         -> { where(status: "lost") }

  def formatted_amount = format_minor_units(amount, currency)

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

  def evidence_submitted?
    evidence_submitted_at.present?
  end

  def evidence_stage
    return :submitted if evidence_submitted_at.present?
    return :draft     if evidence_draft_at.present?
    :none
  end
end
