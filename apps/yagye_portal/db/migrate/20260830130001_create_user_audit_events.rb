# frozen_string_literal: true

class CreateUserAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :user_audit_events, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, index: false, type: :uuid
      t.string :event_type, null: false
      t.string :ip_address
      t.string :user_agent
      t.jsonb  :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :user_audit_events, [ :user_id, :created_at ]
  end
end
