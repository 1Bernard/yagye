# frozen_string_literal: true

require "test_helper"

class MerchantMembershipTest < ActiveSupport::TestCase
  # ── Token generation ────────────────────────────────────────────────────────

  test "generate_invitation_token! returns a [raw, digest] pair" do
    raw, digest = MerchantMembership.generate_invitation_token!
    assert raw.present?
    assert digest.present?
    assert_not_equal raw, digest
    assert_equal Digest::SHA256.hexdigest(raw), digest
  end

  test "generate_invitation_token! returns a unique token on each call" do
    raw1, _ = MerchantMembership.generate_invitation_token!
    raw2, _ = MerchantMembership.generate_invitation_token!
    assert_not_equal raw1, raw2
  end

  # ── Token lookup ────────────────────────────────────────────────────────────

  test "find_by_invitation_token returns the matching membership" do
    raw, digest = MerchantMembership.generate_invitation_token!
    membership  = create(:merchant_membership,
                         state:                   "invited",
                         invitation_token_digest: digest,
                         invitation_expires_at:   7.days.from_now)

    found = MerchantMembership.find_by_invitation_token(raw)
    assert_equal membership, found
  end

  test "find_by_invitation_token returns nil for an unknown token" do
    assert_nil MerchantMembership.find_by_invitation_token("nonexistent-token")
  end

  test "find_by_invitation_token returns nil for an active (already accepted) membership" do
    raw, digest = MerchantMembership.generate_invitation_token!
    create(:merchant_membership,
           state:                   "active",
           invitation_token_digest: digest,
           invitation_expires_at:   7.days.from_now)

    assert_nil MerchantMembership.find_by_invitation_token(raw)
  end

  # ── invitation_valid? ───────────────────────────────────────────────────────

  test "invitation_valid? is true when invited and not expired" do
    _, digest = MerchantMembership.generate_invitation_token!
    membership = build(:merchant_membership,
                       state:                   "invited",
                       invitation_token_digest: digest,
                       invitation_expires_at:   7.days.from_now)
    assert membership.invitation_valid?
  end

  test "invitation_valid? is false when expired" do
    _, digest = MerchantMembership.generate_invitation_token!
    membership = build(:merchant_membership,
                       state:                   "invited",
                       invitation_token_digest: digest,
                       invitation_expires_at:   1.hour.ago)
    refute membership.invitation_valid?
  end

  test "invitation_valid? is false when state is active" do
    _, digest = MerchantMembership.generate_invitation_token!
    membership = build(:merchant_membership,
                       state:                   "active",
                       invitation_token_digest: digest,
                       invitation_expires_at:   7.days.from_now)
    refute membership.invitation_valid?
  end

  test "invitation_valid? is false when token digest is nil" do
    membership = build(:merchant_membership,
                       state:                   "invited",
                       invitation_token_digest: nil,
                       invitation_expires_at:   7.days.from_now)
    refute membership.invitation_valid?
  end

  # ── accept! ─────────────────────────────────────────────────────────────────

  test "accept! transitions state to active and clears the token" do
    _, digest = MerchantMembership.generate_invitation_token!
    membership = create(:merchant_membership,
                        state:                   "invited",
                        invitation_token_digest: digest,
                        invitation_expires_at:   7.days.from_now)

    membership.accept!
    membership.reload

    assert_equal "active", membership.state
    assert_not_nil membership.accepted_at
    assert_nil membership.invitation_token_digest
  end
end
