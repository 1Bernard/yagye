# frozen_string_literal: true

class RefundApprovalsPolicy < ApplicationPolicy
  def index?
    user&.internal_staff? && permitted?("refunds.approve_dispatch")
  end

  def approve?
    user&.internal_staff? && permitted?("refunds.approve_dispatch")
  end

  def reject?
    user&.internal_staff? && permitted?("refunds.approve_dispatch")
  end
end
