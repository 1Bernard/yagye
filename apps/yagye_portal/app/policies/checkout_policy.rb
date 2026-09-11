# frozen_string_literal: true

class CheckoutPolicy < ApplicationPolicy
  # Any authenticated merchant (non-ops) user can manage their payment links.
  def index?         = !internal_staff?
  def create?        = !internal_staff?
  def new?           = !internal_staff?
  def manage_layout? = !internal_staff?

  private

  def internal_staff?
    user.internal_staff?
  end

  def permitted?(permission)
    user.permitted?(permission)
  end
end
