# frozen_string_literal: true

class ReservePolicy < ApplicationPolicy
  def index?       = permitted?("settlements.view")
  def acknowledge? = user.merchant_user? && permitted?("settlements.view")
end
