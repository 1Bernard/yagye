# frozen_string_literal: true

class DevelopersPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
