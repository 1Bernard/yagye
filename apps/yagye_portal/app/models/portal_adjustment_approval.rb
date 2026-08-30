# frozen_string_literal: true

class PortalAdjustmentApproval < ApplicationRecord
  self.table_name = "portal_adjustment_approvals"

  STATES = %w[pending approved rejected].freeze

  scope :pending_review, -> { where(state: "pending").order(proposed_at: :asc) }
  scope :decided,        -> { where.not(state: "pending").order(approved_at: :desc, proposed_at: :desc) }

  def pending?  = state == "pending"
  def approved? = state == "approved"
  def rejected? = state == "rejected"

  def action_summary
    return "—" unless proposed_action.present?
    type = proposed_action["type"] || proposed_action["action"] || "adjustment"
    amount = proposed_action["amount_cents"]
    amount.present? ? "#{type.humanize} · #{Money.new(amount).format}" : type.humanize
  rescue
    proposed_action.to_s.truncate(60)
  end
end
