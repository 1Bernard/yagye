# frozen_string_literal: true

class AddUniqueActiveIndexToPortalMsisdnAllowlists < ActiveRecord::Migration[8.0]
  def change
    add_index :portal_msisdn_allowlists, [:merchant_code, :msisdn],
              unique: true,
              where: "deleted_at IS NULL",
              name: "idx_portal_msisdn_allowlists_unique_active"
  end
end
