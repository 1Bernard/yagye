# frozen_string_literal: true

class DisputesPolicy < ApplicationPolicy
  def index?
    permitted?("payments.view")
  end

  def show?
    permitted?("payments.view")
  end
end
