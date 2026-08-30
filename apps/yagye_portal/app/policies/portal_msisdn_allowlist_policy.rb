# frozen_string_literal: true

class PortalMsisdnAllowlistPolicy < ApplicationPolicy
  def create?  = permitted?("team.manage") || internal_staff?
  def destroy? = permitted?("team.manage") || internal_staff?
end
