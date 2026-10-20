# frozen_string_literal: true

class PortalApiKeyPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(merchant_code: user.merchant_code)
    end
  end

  def index?   = merchant_user? && permitted?("developers.view_api_keys")
  def create?  = merchant_user? && permitted?("developers.manage_api_keys")
  def destroy? = merchant_user? && permitted?("developers.manage_api_keys") &&
                 record.merchant_code == user.merchant_code
end
