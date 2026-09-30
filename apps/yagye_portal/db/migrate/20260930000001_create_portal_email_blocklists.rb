# frozen_string_literal: true

class CreatePortalEmailBlocklists < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_email_blocklists, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :merchant_code, null: false
      t.text :email,         null: false
      t.text :label
      t.text :reason
      t.text :created_by
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :portal_email_blocklists, :merchant_code
    add_index :portal_email_blocklists, :deleted_at
    add_index :portal_email_blocklists, %i[merchant_code email],
              unique: true,
              where: "(deleted_at IS NULL)",
              name: "idx_portal_email_blocklists_unique_active"
  end
end
