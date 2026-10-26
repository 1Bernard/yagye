# frozen_string_literal: true

class ReservePoliciesPolicy < ApplicationPolicy
  def manage?  = internal_staff? && permitted?("reserves.manage")
  def approve? = internal_staff? && permitted?("reserves.approve")
  def view?    = manage? || approve?
end
