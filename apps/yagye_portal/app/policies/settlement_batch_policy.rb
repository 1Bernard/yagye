# frozen_string_literal: true

class SettlementBatchPolicy < ApplicationPolicy
  def index? = permitted?("settlements.view")
  def show?  = permitted?("settlements.view")
end
