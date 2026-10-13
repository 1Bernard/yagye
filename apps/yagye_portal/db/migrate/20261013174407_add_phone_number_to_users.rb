class AddPhoneNumberToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone_number, :string, comment: "E.164 format, e.g. +233201234567. Optional; SMS notifications sent only when present."
    add_index  :users, :phone_number, unique: true, where: "phone_number IS NOT NULL"
  end
end
