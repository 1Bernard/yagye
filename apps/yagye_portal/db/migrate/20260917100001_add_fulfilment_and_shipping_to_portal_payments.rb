class AddFulfilmentAndShippingToPortalPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_payments, :fulfilment_type,        :text
    add_column :portal_payments, :shipping_country,       :text
    add_column :portal_payments, :billing_shipping_match, :boolean
  end
end
