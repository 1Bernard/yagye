# frozen_string_literal: true

class PortalSettlement < ApplicationRecord
  include MoneyDisplayable
  self.table_name  = "portal_settlements"
  self.primary_key = "settlement_code"

  STATES = %w[pending processing settled awaiting_approval dispatch_rejected dispatched reconciling reconciled disputed failed].freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }

  def formatted_expected_net = format_minor_units(expected_net, currency)
  def formatted_reported_net = reported_net ? format_minor_units(reported_net, currency) : "—"
  def period_label           = "#{period_start.strftime("%d %b")} – #{period_end.strftime("%d %b %Y")}"
  def created_at             = last_applied_at
  def dispatched?            = bank_dispatch_ref.present?
  def awaiting_approval?     = state == "awaiting_approval"
  def dispatch_rejected?     = state == "dispatch_rejected"
end
