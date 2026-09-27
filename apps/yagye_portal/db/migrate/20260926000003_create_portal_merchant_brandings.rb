# frozen_string_literal: true

class CreatePortalMerchantBrandings < ActiveRecord::Migration[8.0]
  def change
    create_table :portal_merchant_brandings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :merchant_code, null: false
      t.text :display_name

      t.timestamps
    end

    add_index :portal_merchant_brandings, :merchant_code, unique: true
  end
end
