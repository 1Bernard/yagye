# frozen_string_literal: true

class OnboardingPolicy < ApplicationPolicy
  def index?  = merchant_user?
  def show?   = merchant_user?
  def update? = merchant_user?
  def create? = merchant_user?

  private

  def merchant_user? = user.merchant_user?
end
