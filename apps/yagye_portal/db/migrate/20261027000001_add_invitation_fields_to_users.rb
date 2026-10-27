# frozen_string_literal: true

class AddInvitationFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :invitation_token_digest, :text
    add_column :users, :invitation_expires_at,   :datetime
    add_column :users, :invited_by_id,           :uuid

    add_index :users, :invitation_token_digest,
              unique: true,
              where:  "invitation_token_digest IS NOT NULL",
              name:   "index_users_on_invitation_token_digest"

    add_foreign_key :users, :users, column: :invited_by_id
  end
end
