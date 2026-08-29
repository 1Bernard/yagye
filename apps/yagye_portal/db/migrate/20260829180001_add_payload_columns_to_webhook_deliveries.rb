class AddPayloadColumnsToWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_webhook_deliveries, :event_id,        :text
    add_column :portal_webhook_deliveries, :request_headers, :jsonb
    add_column :portal_webhook_deliveries, :request_body,    :jsonb
    add_column :portal_webhook_deliveries, :response_body,   :text
    add_column :portal_webhook_deliveries, :duration_ms,     :integer
  end
end
