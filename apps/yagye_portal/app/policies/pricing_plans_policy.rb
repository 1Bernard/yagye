# frozen_string_literal: true

class PricingPlansPolicy < ApplicationPolicy
  def index?
    internal_staff?
  end

  def show?
    internal_staff?
  end

  def create?
    internal_staff? && user.permitted?("merchants.approve")
  end

  def update?
    internal_staff? && user.permitted?("merchants.approve")
  end
end
