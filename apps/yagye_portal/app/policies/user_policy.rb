# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def invite?
    permitted?("team.manage") || internal_staff?
  end

  def update?
    permitted?("team.manage") || internal_staff?
  end

  def destroy?
    internal_staff? || (permitted?("team.manage") && record != user)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?
      scope.joins(:merchant_memberships)
           .where(merchant_memberships: { merchant_code: user.merchant_code, state: "active" })
    end
  end
end
