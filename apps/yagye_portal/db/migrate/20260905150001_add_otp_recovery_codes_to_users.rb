# frozen_string_literal: true

class AddOtpRecoveryCodesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_recovery_codes, :text
  end
end
