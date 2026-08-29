class CreateDeveloperReadModels < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_api_keys, id: false, primary_key: :key_id do |t|
      t.uuid   :key_id,          null: false
      t.text   :merchant_code,   null: false
      t.text   :mode,            null: false
      t.text   :kind,            null: false  # publishable | secret
      t.text   :label,           null: false, default: ""
      t.text   :key_prefix,      null: false  # first 24 chars only — never raw key or hash
      t.text   :scopes,          array: true, null: false, default: []
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.datetime :expires_at
      t.text   :created_by
      t.text   :last_event_id,   null: false, default: ""
      t.datetime :last_applied_at, null: false, default: -> { "NOW()" }
      t.datetime :created_at,    null: false, default: -> { "NOW()" }
    end

    execute "ALTER TABLE portal_api_keys ADD PRIMARY KEY (key_id);"
    add_index :portal_api_keys, :merchant_code
    add_index :portal_api_keys, %i[merchant_code mode]
    add_index :portal_api_keys, :revoked_at

    create_table :portal_webhook_endpoints, id: false, primary_key: :endpoint_id do |t|
      t.uuid   :endpoint_id,           null: false
      t.text   :merchant_code,         null: false
      t.text   :mode,                  null: false
      t.text   :url,                   null: false
      t.text   :subscribed_events,     array: true, null: false, default: []
      t.boolean :active,               null: false, default: true
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :disabled_at
      t.text :last_event_id,         null: false, default: ""
      t.datetime :last_applied_at,     null: false, default: -> { "NOW()" }
      t.datetime :created_at,          null: false, default: -> { "NOW()" }
    end

    execute "ALTER TABLE portal_webhook_endpoints ADD PRIMARY KEY (endpoint_id);"
    add_index :portal_webhook_endpoints, :merchant_code
    add_index :portal_webhook_endpoints, %i[merchant_code mode]

    create_table :portal_webhook_deliveries, id: false, primary_key: :delivery_id do |t|
      t.uuid   :delivery_id,       null: false
      t.uuid   :endpoint_id,       null: false
      t.text   :merchant_code,     null: false
      t.text   :event_type,        null: false
      t.text   :state,             null: false  # pending|delivering|delivered|failed|exhausted
      t.integer :response_status
      t.integer :attempt,          null: false, default: 1
      t.datetime :delivered_at
      t.datetime :last_applied_at, null: false, default: -> { "NOW()" }
    end

    execute "ALTER TABLE portal_webhook_deliveries ADD PRIMARY KEY (delivery_id);"
    add_index :portal_webhook_deliveries, :endpoint_id
    add_index :portal_webhook_deliveries, %i[endpoint_id last_applied_at]
    add_index :portal_webhook_deliveries, :merchant_code
  end
end
