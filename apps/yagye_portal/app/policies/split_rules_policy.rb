# frozen_string_literal: true

class SplitRulesPolicy < ApplicationPolicy
  def index?      = permitted?("payments.view")
  def create?     = permitted?("payments.manage")
  def deactivate? = permitted?("payments.manage")
end
