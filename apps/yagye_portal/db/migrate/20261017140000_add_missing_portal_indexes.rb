# frozen_string_literal: true

class AddMissingPortalIndexes < ActiveRecord::Migration[8.1]
  def change
    # merchant lookup by code (used on almost every request)
    add_index :portal_merchants, :merchant_code, unique: true,
              if_not_exists: true

    # event sourcing — last_event_id on every projection table
    add_index :portal_merchants,             :last_event_id, if_not_exists: true
    add_index :portal_merchant_applications, :last_event_id, if_not_exists: true
    add_index :portal_webhook_endpoints,     :last_event_id, if_not_exists: true
    add_index :portal_api_keys,              :last_event_id, if_not_exists: true
    add_index :portal_adjustment_approvals,  :last_event_id, if_not_exists: true
    add_index :portal_disputes,              :last_event_id, if_not_exists: true
    add_index :portal_payouts,               :last_event_id, if_not_exists: true
    add_index :portal_settlements,           :last_event_id, if_not_exists: true

    # FK / lookup columns
    add_index :portal_webhook_endpoints, :endpoint_id, if_not_exists: true
    add_index :portal_api_keys,          :key_id,      if_not_exists: true
    add_index :portal_disputes,          :core_payment_id, if_not_exists: true

    # webhook delivery lookups
    add_index :portal_webhook_deliveries, :delivery_id, if_not_exists: true
    add_index :portal_webhook_deliveries, :event_id,    if_not_exists: true
  end
end
