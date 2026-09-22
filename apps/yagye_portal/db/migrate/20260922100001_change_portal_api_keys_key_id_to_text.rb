# frozen_string_literal: true

# key_id stores Core's public_id ("key_<uuid7>"), which is a prefixed string,
# not a bare UUID.  The original :uuid column type silently cast the prefixed
# value to nil, causing NOT NULL violations on every upsert.
class ChangePortalApiKeysKeyIdToText < ActiveRecord::Migration[8.0]
  def up
    execute "ALTER TABLE portal_api_keys ALTER COLUMN key_id TYPE text"
  end

  def down
    execute "ALTER TABLE portal_api_keys ALTER COLUMN key_id TYPE uuid USING key_id::uuid"
  end
end
