# frozen_string_literal: true

class ReservePolicy < ApplicationPolicy
  def index?       = permitted?("settlements.view")
  def acknowledge? = current_user.merchant_user? && permitted?("settlements.view")
end
