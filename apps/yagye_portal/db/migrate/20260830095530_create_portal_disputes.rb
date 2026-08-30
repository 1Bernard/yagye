class CreatePortalDisputes < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_disputes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text     :core_dispute_id,   null: false
      t.text     :merchant_code,     null: false
      t.text     :reference,         null: false
      t.text     :core_payment_id
      t.text     :payment_reference
      t.bigint   :amount_cents,      null: false
      t.text     :currency,          null: false, default: "GHS"
      t.text     :reason,            null: false  # fraud|duplicate|not_received|unrecognised|other
      t.text     :status,            null: false  # submitted|under_review|won|lost|closed
      t.text     :customer_msisdn
      t.text     :network_deadline
      t.datetime :opened_at
      t.datetime :resolved_at
      t.text     :last_event_id,     null: false, default: ""
      t.datetime :last_applied_at,   null: false, default: -> { "NOW()" }
      t.timestamps
    end

    add_index :portal_disputes, :core_dispute_id, unique: true
    add_index :portal_disputes, :merchant_code
    add_index :portal_disputes, :status
    add_index :portal_disputes, :reference, unique: true
    add_index :portal_disputes, %i[merchant_code status]
    add_index :portal_disputes, %i[merchant_code created_at]
  end
end
