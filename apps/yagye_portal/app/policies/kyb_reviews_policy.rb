# frozen_string_literal: true

class KybReviewsPolicy < ApplicationPolicy
  def index?
    internal_staff?
  end

  def show?
    internal_staff?
  end
end
