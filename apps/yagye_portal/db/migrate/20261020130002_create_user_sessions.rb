# frozen_string_literal: true

class CreateUserSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :session_token_digest, null: false
      t.text :device_fingerprint, null: false
      t.text :ip
      t.text :user_agent_hash
      t.datetime :mfa_satisfied_at, precision: 6
      t.datetime :expires_at, null: false, precision: 6
      t.datetime :revoked_at, precision: 6
      t.datetime :created_at, null: false, precision: 6
    end

    add_index :user_sessions, :session_token_digest, unique: true
    add_index :user_sessions, [ :user_id, :revoked_at ], name: "index_user_sessions_on_user_id_and_revoked_at"
    add_index :user_sessions, :expires_at, name: "index_user_sessions_on_expires_at"
  end
end
