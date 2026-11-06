# frozen_string_literal: true

class DevelopersPolicy < ApplicationPolicy
  def index?                  = user.present?
  def manage_keys?            = permitted?("developers.manage_api_keys")
  def manage_webhooks?        = permitted?("developers.manage_webhooks")
  def manage_routing_rules?   = internal_staff?
  # Merchant PSP connections — any merchant user (tier gate enforced in controller)
  def manage_psp_connections? = merchant_user?
  # Merchant self-service routing graph — any merchant user (tier gate enforced in controller)
  def manage_merchant_routing? = merchant_user?
end
