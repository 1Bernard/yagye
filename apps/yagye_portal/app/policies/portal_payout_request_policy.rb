# frozen_string_literal: true

class PortalPayoutRequestPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.for_merchant(user.merchant_code)
    end
  end

  def index?  = user.permitted?("payouts.view")
  def show?   = user.permitted?("payouts.view")
  def new?    = create?
  def create? = !user.internal_staff? && user.permitted?("payouts.request")
  def review? = user.internal_staff? && user.permitted?("payouts.review_requests")
end
