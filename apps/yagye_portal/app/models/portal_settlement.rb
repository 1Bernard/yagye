# frozen_string_literal: true

class PortalSettlement < ApplicationRecord
  self.table_name  = "portal_settlements"
  self.primary_key = "settlement_code"

  STATES = %w[pending processing reconciling reconciled disputed failed].freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }

  def formatted_expected_net = "#{currency} #{"%.2f" % (expected_net / 100.0)}"
  def formatted_reported_net = reported_net ? "#{currency} #{"%.2f" % (reported_net / 100.0)}" : "—"
  def period_label           = "#{period_start.strftime("%d %b")} – #{period_end.strftime("%d %b %Y")}"
  def created_at = last_applied_at
end
