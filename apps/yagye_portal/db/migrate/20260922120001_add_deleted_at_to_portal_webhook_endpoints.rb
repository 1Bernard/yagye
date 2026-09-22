class AddDeletedAtToPortalWebhookEndpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_webhook_endpoints, :deleted_at, :datetime
    add_index  :portal_webhook_endpoints, :deleted_at
  end
end
