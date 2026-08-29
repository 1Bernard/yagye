class CreateVersions < ActiveRecord::Migration[8.1]
  # PaperTrail standard schema.
  # item_id is TEXT from day one — retrofitting string PKs after UUID models
  # exist is painful (see yagye-portal.dbml note on versions table).
  # NEVER enable PaperTrail on portal_* read models (portal_payments,
  # portal_merchant_applications) — those are rebuilt from Core events, not versioned.
  def change
    create_table :versions do |t|
      t.text   :item_type,     null: false
      t.text   :item_id,       null: false  # string to support UUID PKs
      t.text   :event,         null: false
      t.text   :whodunnit
      t.jsonb  :object
      t.jsonb  :object_changes
      t.datetime :created_at, precision: 6
    end

    add_index :versions, %i[item_type item_id]
    add_index :versions, :created_at
  end
end
