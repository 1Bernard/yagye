# frozen_string_literal: true

class CreatePortalAllowlists < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_ip_allowlists, id: :uuid do |t|
      t.text :merchant_code, null: false
      t.text :cidr,          null: false
      t.text :label
      t.text :created_by
      t.timestamps null: false
    end
    add_index :portal_ip_allowlists, :merchant_code

    create_table :portal_msisdn_allowlists, id: :uuid do |t|
      t.text :merchant_code, null: false
      t.text :msisdn,        null: false
      t.text :label
      t.text :created_by
      t.timestamps null: false
    end
    add_index :portal_msisdn_allowlists, :merchant_code
  end
end
