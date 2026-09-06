# frozen_string_literal: true

class RolePolicy < ApplicationPolicy
  def index? = user.present?
  def show?  = user.present?

  def create?  = user.internal_staff?
  def new?     = create?
  def update?  = user.internal_staff?
  def edit?    = update?
  def destroy? = user.internal_staff? && !record.system_role? && record.user_roles.none?
end
