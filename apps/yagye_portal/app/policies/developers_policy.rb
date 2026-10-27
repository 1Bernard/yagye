# frozen_string_literal: true

class DevelopersPolicy < ApplicationPolicy
  def index?                = merchant_user?
  def manage_keys?          = permitted?("developers.manage_api_keys")
  def manage_webhooks?      = permitted?("developers.manage_webhooks")
  def manage_routing_rules? = internal_staff?
end
