class CreatePortalPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_payments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text     :core_payment_id, null: false
      t.text     :merchant_code,   null: false
      t.text     :reference
      t.text     :customer_msisdn
      t.text     :customer_email
      t.bigint   :amount_cents,    null: false
      t.text     :currency,        null: false, default: "GHS"
      t.text     :status,          null: false
      t.text     :provider
      t.text     :description
      t.jsonb    :metadata,        null: false, default: {}
      t.datetime :paid_at
      t.timestamps
    end

    add_index :portal_payments, :core_payment_id, unique: true
    add_index :portal_payments, :merchant_code
    add_index :portal_payments, :status
    add_index :portal_payments, %i[merchant_code created_at]
    add_index :portal_payments, :reference
  end
end
