# frozen_string_literal: true

class AddDeletedAtToPortalMsisdnAllowlists < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_msisdn_allowlists, :deleted_at, :datetime, precision: 6
    add_index  :portal_msisdn_allowlists, :deleted_at
  end
end
