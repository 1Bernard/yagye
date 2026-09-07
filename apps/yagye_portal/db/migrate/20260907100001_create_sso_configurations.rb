class CreateSsoConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :sso_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :name,               null: false
      t.string  :email_domain,       null: false
      t.string  :merchant_code,      null: false
      t.string  :idp_sso_target_url, null: false
      t.string  :idp_entity_id
      t.text    :idp_cert,           null: false
      t.boolean :active,             null: false, default: true

      t.timestamps
    end

    add_index :sso_configurations, :email_domain, unique: true
    add_index :sso_configurations, :merchant_code
  end
end
