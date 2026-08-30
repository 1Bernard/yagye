# frozen_string_literal: true

class AddPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :theme_preference,    :string, null: false, default: "system"
    add_column :users, :language_preference, :string, null: false, default: "en"
  end
end
