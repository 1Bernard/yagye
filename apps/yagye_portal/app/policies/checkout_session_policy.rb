# frozen_string_literal: true

class CheckoutSessionPolicy < ApplicationPolicy
  def index? = !user.internal_staff?
  def show?  = !user.internal_staff?
end
