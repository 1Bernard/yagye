# frozen_string_literal: true

class CreatePortalMerchantBalances < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_merchant_balances, id: false do |t|
      t.text :merchant_code, null: false
      t.string :currency, limit: 3, null: false
      t.text :mode, null: false
      t.bigint :available, null: false, default: 0
      t.bigint :pending, null: false, default: 0
      t.bigint :reserved, null: false, default: 0
      t.bigint :in_transit, null: false, default: 0
      t.text :last_event_id
      t.datetime :last_applied_at, null: false, precision: 6
    end

    execute "ALTER TABLE portal_merchant_balances ADD PRIMARY KEY (merchant_code, currency, mode)"
    add_index :portal_merchant_balances, :merchant_code, name: "index_portal_merchant_balances_on_merchant_code"
  end
end
