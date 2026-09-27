# frozen_string_literal: true

class PortalMerchantBrandingPolicy < ApplicationPolicy
  def update? = permitted?("team.manage") || internal_staff?
end
