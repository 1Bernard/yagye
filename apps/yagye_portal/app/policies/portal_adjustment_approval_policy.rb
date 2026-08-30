# frozen_string_literal: true

class PortalAdjustmentApprovalPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.internal_staff?
      scope.none
    end
  end

  def index?   = internal_staff?
  def approve? = internal_staff? && permitted?("merchants.approve")
  def reject?  = approve?
end
