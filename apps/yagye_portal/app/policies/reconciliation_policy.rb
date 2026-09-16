# frozen_string_literal: true

class ReconciliationPolicy < ApplicationPolicy
  def index?               = internal_staff?
  def show?                = internal_staff?
  def propose_adjustment?  = internal_staff?
end
