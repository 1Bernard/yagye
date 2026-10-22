# frozen_string_literal: true

class CreatePortalDailyMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_daily_metrics, id: false do |t|
      t.text :merchant_code, null: false
      t.date :day, null: false
      t.string :currency, limit: 3, null: false
      t.text :mode, null: false
      t.integer :payment_count, null: false, default: 0
      t.integer :succeeded_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.bigint :gross_volume, null: false, default: 0
      t.bigint :refund_volume, null: false, default: 0
      t.integer :chargeback_count, null: false, default: 0
    end

    execute "ALTER TABLE portal_daily_metrics ADD PRIMARY KEY (merchant_code, day, currency, mode)"
    add_index :portal_daily_metrics, [ :merchant_code, :day ],
              name: "index_portal_daily_metrics_on_merchant_code_and_day"
  end
end
