# frozen_string_literal: true

class SettingsPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
