# frozen_string_literal: true

class KycPolicy < ApplicationPolicy
  def index? = merchant_user?
end
