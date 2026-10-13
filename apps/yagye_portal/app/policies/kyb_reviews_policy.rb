# frozen_string_literal: true

class KybReviewsPolicy < ApplicationPolicy
  def index?          = internal_staff?
  def show?           = internal_staff?
  def assign?         = internal_staff?
  def approve?        = internal_staff? && permitted?("kyb.approve_merchant")
  def grant_sandbox?  = internal_staff? && (permitted?("kyb.approve_merchant") || permitted?("merchants.approve"))
end
