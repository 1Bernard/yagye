# frozen_string_literal: true

class CreateProcessedEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_events, id: false do |t|
      t.text :event_id, null: false
      t.text :consumer, null: false
      t.datetime :processed_at, null: false, precision: 6
    end

    execute "ALTER TABLE processed_events ADD PRIMARY KEY (event_id, consumer)"
    add_index :processed_events, :processed_at, name: "index_processed_events_on_processed_at"
  end
end
