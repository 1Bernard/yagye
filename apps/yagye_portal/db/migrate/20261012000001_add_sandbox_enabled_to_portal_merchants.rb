# frozen_string_literal: true

class AddSandboxEnabledToPortalMerchants < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_merchants, :sandbox_enabled, :boolean, null: false, default: false
  end
end
