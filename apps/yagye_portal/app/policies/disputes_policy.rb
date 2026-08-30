# frozen_string_literal: true

class DisputesPolicy < ApplicationPolicy
  def index?  = permitted?("payments.view")
  def show?   = permitted?("payments.view")
  def update? = permitted?("payments.dispute")

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.for_merchant(user.merchant_code)
    end
  end
end
