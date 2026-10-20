# frozen_string_literal: true

class PortalAdjustmentApproval < ApplicationRecord
  self.table_name = "portal_adjustment_approvals"

  STATES = %w[pending approved rejected].freeze

  scope :pending_review, -> { where(state: "pending").order(proposed_at: :asc) }
  scope :decided,        -> { where.not(state: "pending").order(updated_at: :desc) }

  def pending?  = state == "pending"
  def approved? = state == "approved"
  def rejected? = state == "rejected"

  def action_summary
    return "—" unless proposed_action.present?
    type = proposed_action["type"] || proposed_action["action"] || "adjustment"
    amount = proposed_action["amount"]
    amount.present? ? "#{type.humanize} · #{format_minor_units(amount.to_i)}" : type.humanize
  rescue StandardError
    proposed_action.to_s.truncate(60)
  end

  private

  def format_minor_units(minor_units)
    n = minor_units / 100.0
    whole, frac = format("%.2f", n).split(".")
    "GHS #{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}.#{frac}"
  end
end
