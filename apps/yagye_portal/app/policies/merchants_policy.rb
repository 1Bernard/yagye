# frozen_string_literal: true

class MerchantsPolicy < ApplicationPolicy
  def index?
    internal_staff?
  end

  def show?
    internal_staff?
  end

  def update?
    user.permitted?("merchants.approve") || user.permitted?("merchants.suspend")
  end
end
