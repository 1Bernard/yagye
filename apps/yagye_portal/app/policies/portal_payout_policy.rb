# frozen_string_literal: true

class PortalPayoutPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index? = user.permitted?("payouts.view")
  def show?  = user.permitted?("payouts.view")
end
