class AddFeeColumnsToPortalPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_payments, :fee_amount, :bigint
    add_column :portal_payments, :net_amount, :bigint
  end
end
