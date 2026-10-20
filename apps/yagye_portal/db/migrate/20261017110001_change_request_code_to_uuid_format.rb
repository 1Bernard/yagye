# frozen_string_literal: true

class ChangeRequestCodeToUuidFormat < ActiveRecord::Migration[8.0]
  def up
    PortalPayoutRequest.reset_column_information
    PortalPayoutRequest.find_each do |r|
      r.update_column(:request_code, SecureRandom.uuid)
    end
  end

  def down
    # Not reversible — previous prq_ codes are not stored
    raise ActiveRecord::IrreversibleMigration
  end
end
