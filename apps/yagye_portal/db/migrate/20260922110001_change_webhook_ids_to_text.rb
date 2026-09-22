class ChangeWebhookIdsToText < ActiveRecord::Migration[8.1]
  def up
    # Core public IDs carry prefixes (whe_…, whdl_…) — not valid UUIDs.
    # Rails' uuid type casts them to nil, causing NOT NULL violations on upsert.
    change_column :portal_webhook_endpoints, :endpoint_id, :text, null: false
    change_column :portal_webhook_deliveries, :delivery_id, :text, null: false
    change_column :portal_webhook_deliveries, :endpoint_id, :text, null: false
  end

  def down
    change_column :portal_webhook_endpoints, :endpoint_id, :uuid, null: false, using: "endpoint_id::uuid"
    change_column :portal_webhook_deliveries, :delivery_id, :uuid, null: false, using: "delivery_id::uuid"
    change_column :portal_webhook_deliveries, :endpoint_id, :uuid, null: false, using: "endpoint_id::uuid"
  end
end
