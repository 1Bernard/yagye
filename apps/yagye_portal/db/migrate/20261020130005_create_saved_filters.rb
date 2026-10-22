# frozen_string_literal: true

class CreateSavedFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :saved_filters do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :namespace, null: false
      t.text :name, null: false
      t.jsonb :filters, null: false, default: {}
      t.boolean :shared_with_merchant, null: false, default: false
      t.timestamps
    end

    add_index :saved_filters, [ :user_id, :namespace ], name: "index_saved_filters_on_user_id_and_namespace"
  end
end
