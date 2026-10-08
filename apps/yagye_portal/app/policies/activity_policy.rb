# frozen_string_literal: true

class ActivityPolicy < ApplicationPolicy
  def index? = user.present?
end
