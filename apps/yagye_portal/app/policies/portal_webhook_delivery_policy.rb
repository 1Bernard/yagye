# frozen_string_literal: true

class PortalWebhookDeliveryPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index? = merchant_user? && permitted?("developers.manage_webhooks")
  def show?  = merchant_user? && permitted?("developers.manage_webhooks") &&
               record.merchant_code == user.merchant_code
end
