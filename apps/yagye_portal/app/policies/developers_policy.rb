# frozen_string_literal: true

class DevelopersPolicy < ApplicationPolicy
  def index?          = user.present?
  def manage_keys?    = permitted?("developers.manage") || internal_staff?
  def manage_webhooks? = permitted?("developers.manage") || internal_staff?
end
