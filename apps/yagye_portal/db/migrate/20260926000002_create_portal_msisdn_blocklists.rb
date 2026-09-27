# frozen_string_literal: true

class CreatePortalMsisdnBlocklists < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_msisdn_blocklists, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :merchant_code, null: false
      t.text :msisdn,        null: false
      t.text :label
      t.text :reason
      t.text :created_by
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :portal_msisdn_blocklists, :merchant_code
    add_index :portal_msisdn_blocklists, :deleted_at
    add_index :portal_msisdn_blocklists, %i[merchant_code msisdn],
              unique: true,
              where: "(deleted_at IS NULL)",
              name: "idx_portal_msisdn_blocklists_unique_active"
  end
end
