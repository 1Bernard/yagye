# frozen_string_literal: true

class PortalWebhookDeliveryPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index? = internal_staff? || (merchant_user? && permitted?("developers.manage_webhooks"))
  def show?  = internal_staff? ||
               (merchant_user? && permitted?("developers.manage_webhooks") &&
                record.merchant_code == user.merchant_code)
end
