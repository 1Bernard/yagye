# frozen_string_literal: true

class CreatePortalPayoutsAndSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_payouts, id: false do |t|
      t.text     :payout_code,             null: false, primary_key: true
      t.text     :merchant_code,           null: false
      t.text     :mode,                    null: false
      t.integer  :aggregate_version,       null: false, default: 1
      t.text     :state,                   null: false
      t.bigint   :amount,                  null: false
      t.string   :currency, limit: 3,      null: false
      t.text     :destination_type,        null: false
      t.text     :destination_fingerprint, null: false
      t.date     :scheduled_for,           null: false
      t.text     :failure_code
      t.text     :last_event_id,           null: false
      t.datetime :last_applied_at,         null: false
    end
    add_index :portal_payouts, :merchant_code
    add_index :portal_payouts, %i[merchant_code scheduled_for]

    create_table :portal_settlements, id: false do |t|
      t.text     :settlement_code,   null: false, primary_key: true
      t.text     :merchant_code,     null: false
      t.text     :provider_code,     null: false
      t.text     :mode,              null: false
      t.integer  :aggregate_version, null: false, default: 1
      t.text     :state,             null: false
      t.string   :currency, limit: 3, null: false
      t.datetime :period_start,      null: false
      t.datetime :period_end,        null: false
      t.bigint   :expected_net,      null: false
      t.bigint   :reported_net
      t.bigint   :variance
      t.date     :value_date
      t.integer  :item_count
      t.text     :last_event_id,     null: false
      t.datetime :last_applied_at,   null: false
    end
    add_index :portal_settlements, :merchant_code
  end
end
