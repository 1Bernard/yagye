# frozen_string_literal: true

class CustomerPolicy < ApplicationPolicy
  def index? = permitted?("payments.view")
  def show?  = permitted?("payments.view")
end
