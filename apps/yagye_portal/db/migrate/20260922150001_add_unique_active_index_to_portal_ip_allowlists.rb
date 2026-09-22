# frozen_string_literal: true

class AddUniqueActiveIndexToPortalIpAllowlists < ActiveRecord::Migration[8.0]
  def change
    add_index :portal_ip_allowlists, [:merchant_code, :cidr],
              unique: true,
              where: "deleted_at IS NULL",
              name: "idx_portal_ip_allowlists_unique_active"
  end
end
