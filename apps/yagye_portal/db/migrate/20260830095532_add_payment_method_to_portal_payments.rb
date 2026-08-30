class AddPaymentMethodToPortalPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_payments, :payment_method, :text
    add_column :portal_payments, :settled_at, :datetime
    add_index  :portal_payments, :payment_method
  end
end
