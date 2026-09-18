# frozen_string_literal: true

class ReservePolicy < ApplicationPolicy
  def index? = permitted?("settlements.view")
end
