class AddGrossAndFeesToPortalSettlements < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_settlements, :gross_amount, :bigint
    add_column :portal_settlements, :platform_fees, :bigint
  end
end
