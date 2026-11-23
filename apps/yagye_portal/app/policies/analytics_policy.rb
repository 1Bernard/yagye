# frozen_string_literal: true

class AnalyticsPolicy < ApplicationPolicy
  def view?
    user.present?
  end
end
