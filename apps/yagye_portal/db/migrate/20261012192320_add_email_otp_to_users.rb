class AddEmailOtpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_otp_digest, :string
    add_column :users, :email_otp_expires_at, :datetime
  end
end
