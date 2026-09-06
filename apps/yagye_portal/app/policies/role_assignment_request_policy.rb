# frozen_string_literal: true

class RoleAssignmentRequestPolicy < ApplicationPolicy
  # record is a RoleAssignmentRequest instance (or the class for collection actions)

  def index?
    internal_staff? && permitted?("team.manage")
  end

  def approve?
    internal_staff? && permitted?("team.manage") && record.requested_by != user
  end

  def reject?
    approve?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.internal_staff?
      scope.all
    end
  end
end
