class CreatePortalMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_merchants, id: false, primary_key: :merchant_code do |t|
      t.text     :merchant_code,     null: false
      t.integer  :aggregate_version, null: false, default: 0
      t.text     :status,            null: false, default: "registered"
      t.text     :onboarding_state,  null: false, default: "not_started"
      t.text     :legal_name,        null: false, default: ""
      t.text     :trading_name,      null: false, default: ""
      t.text     :country,           null: false, default: ""
      t.text     :default_currency,  null: false, default: "GHS"
      t.text     :risk_rating
      t.text     :activity_state,    null: false, default: "inactive"
      t.boolean  :live_mode_enabled, null: false, default: false
      t.text     :last_event_id,     null: false, default: ""
      t.datetime :last_applied_at,   null: false, default: -> { "NOW()" }
    end
  end
end
