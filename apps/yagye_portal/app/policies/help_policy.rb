# frozen_string_literal: true

class HelpPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
