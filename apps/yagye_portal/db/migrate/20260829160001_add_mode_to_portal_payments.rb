class AddModeToPortalPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_payments, :mode, :text, null: false, default: "test"
    add_index  :portal_payments, :mode
    add_index  :portal_payments, %i[merchant_code mode]
  end
end
