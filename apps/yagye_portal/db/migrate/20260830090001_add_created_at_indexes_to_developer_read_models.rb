# frozen_string_literal: true

# The developer tab queries filter by (merchant_code, mode) then ORDER BY created_at DESC.
# Without a covering index, Postgres must sort the already-filtered set in memory.
# Adding created_at to the composite index lets the sort be served by an index scan.
class AddCreatedAtIndexesToDeveloperReadModels < ActiveRecord::Migration[8.1]
  def change
    # Replace (merchant_code, mode) with (merchant_code, mode, created_at DESC)
    remove_index :portal_api_keys, name: "index_portal_api_keys_on_merchant_code_and_mode"
    add_index :portal_api_keys, %i[merchant_code mode created_at],
              order: { created_at: :desc },
              name: "index_portal_api_keys_on_merchant_code_mode_created_at"

    remove_index :portal_webhook_endpoints, name: "index_portal_webhook_endpoints_on_merchant_code_and_mode"
    add_index :portal_webhook_endpoints, %i[merchant_code mode created_at],
              order: { created_at: :desc },
              name: "index_portal_webhook_endpoints_on_merchant_code_mode_created_at"
  end
end
