# frozen_string_literal: true

class AddIndexToInvitationTokenDigest < ActiveRecord::Migration[8.0]
  def change
    # Partial unique index: only non-null digests must be unique.
    # Accepted memberships have digest set to nil, so they don't block re-invites.
    add_index :merchant_memberships, :invitation_token_digest,
              unique: true,
              where:  "invitation_token_digest IS NOT NULL",
              name:   "index_merchant_memberships_on_invitation_token_digest"
  end
end
