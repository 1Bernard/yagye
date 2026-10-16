# frozen_string_literal: true

class PayoutDestinationsPolicy < ApplicationPolicy
  def verify? = user.internal_staff?
end
