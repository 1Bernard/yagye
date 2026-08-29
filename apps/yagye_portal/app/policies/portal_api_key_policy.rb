# frozen_string_literal: true

class PortalApiKeyPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.internal_staff?
        scope.all
      else
        scope.where(merchant_code: user.merchant_code)
      end
    end
  end

  def index?  = user.present?
  def create? = user.present?
  def destroy? = own_record?

  private

  def own_record?
    user.internal_staff? || record.merchant_code == user.merchant_code
  end
end
