# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Lockable
      t.integer  :failed_attempts, default: 0, null: false
      t.string   :unlock_token
      t.datetime :locked_at

      ## TOTP (devise-two-factor)
      t.string  :otp_secret
      t.integer :consumed_timestep
      t.boolean :otp_required_for_login, default: false, null: false

      ## Profile & role
      t.string :first_name
      t.string :last_name
      t.string :role, null: false, default: "merchant_read_only"

      ## Merchant scoping (nil for ops users)
      t.string :merchant_public_id

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :unlock_token,         unique: true
    add_index :users, :merchant_public_id
    add_index :users, :role
  end
end
