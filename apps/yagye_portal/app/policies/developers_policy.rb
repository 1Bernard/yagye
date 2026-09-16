# frozen_string_literal: true

class DevelopersPolicy < ApplicationPolicy
  def index?               = user.present?
  def manage_keys?         = permitted?("developers.manage_api_keys") || internal_staff?
  def manage_webhooks?     = permitted?("developers.manage_webhooks") || internal_staff?
  def manage_routing_rules? = internal_staff?
end
