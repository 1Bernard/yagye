# frozen_string_literal: true

class KybReviewsPolicy < ApplicationPolicy
  def index?   = internal_staff?
  def show?    = internal_staff?
  def approve? = internal_staff? && permitted?("kyb.approve")
end
