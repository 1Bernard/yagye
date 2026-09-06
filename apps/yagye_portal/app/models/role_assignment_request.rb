# frozen_string_literal: true

class RoleAssignmentRequest < ApplicationRecord
  belongs_to :target_user,  class_name: "User"
  belongs_to :requested_by, class_name: "User"
  belongs_to :reviewed_by,  class_name: "User", optional: true

  STATUSES = %w[pending approved rejected cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validate :no_self_request
  validate :no_self_approve, if: :reviewed_by_id?

  scope :pending,  -> { where(status: "pending") }
  scope :decided,  -> { where.not(status: "pending") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(target_user: user) }

  def pending?   = status == "pending"
  def approved?  = status == "approved"
  def rejected?  = status == "rejected"
  def cancelled? = status == "cancelled"

  def added_keys   = requested_role_keys - current_role_keys
  def removed_keys = current_role_keys - requested_role_keys
  def no_change?   = added_keys.empty? && removed_keys.empty?

  private

  def no_self_request
    return unless target_user_id.present? && requested_by_id.present?
    errors.add(:base, "Cannot request a role change for yourself") if target_user_id == requested_by_id
  end

  def no_self_approve
    errors.add(:base, "Requester and approver must be different people") if reviewed_by_id == requested_by_id
  end
end
