# frozen_string_literal: true

class PortalEmailBlocklistPolicy < ApplicationPolicy
  def create?  = permitted?("team.manage") || internal_staff?
  def destroy? = permitted?("team.manage") || internal_staff?
end
