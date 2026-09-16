# frozen_string_literal: true

class CreatePortalPayoutRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_payout_requests do |t|
      t.text     :merchant_code,  null: false
      t.text     :requested_by,   null: false   # user_code of the requester
      t.bigint   :amount_cents                  # nil = full unsettled balance
      t.string   :currency,       null: false, limit: 3, default: "GHS"
      t.text     :reason,         null: false
      t.text     :state,          null: false, default: "pending"
      t.text     :reviewed_by                   # ops user_code
      t.text     :reviewer_note
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :portal_payout_requests, :merchant_code
    add_index :portal_payout_requests, :state
    add_index :portal_payout_requests, [ :merchant_code, :state ]
  end
end
