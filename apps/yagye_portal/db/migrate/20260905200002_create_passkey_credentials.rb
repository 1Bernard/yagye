class CreatePasskeyCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :passkey_credentials, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string  :external_id, null: false
      t.text    :public_key,  null: false
      t.integer :sign_count,  null: false, default: 0
      t.string  :nickname
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :passkey_credentials, :external_id, unique: true
  end
end
