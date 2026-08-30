# frozen_string_literal: true

class PortalSettlementPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index? = user.permitted?("settlements.view")
  def show?  = user.permitted?("settlements.view")
end
