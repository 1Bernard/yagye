# frozen_string_literal: true

class CreatePortalIpBlocklists < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_ip_blocklists, id: :uuid do |t|
      t.string  :merchant_code, null: false, index: true
      t.string  :cidr,          null: false
      t.string  :label
      t.string  :reason
      t.string  :created_by
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :portal_ip_blocklists, %i[merchant_code cidr],
              unique: true,
              where: "deleted_at IS NULL",
              name:  "index_portal_ip_blocklists_on_merchant_and_cidr_active"
  end
end
