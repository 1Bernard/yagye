# frozen_string_literal: true

class PortalWebhookDeliveryPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index?  = user.present?
  def show?   = own_record?

  private

  def own_record?
    user.internal_staff? || record.merchant_code == user.merchant_code
  end
end
