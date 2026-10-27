# frozen_string_literal: true

require "test_helper"
require "support/integration_helpers"

# ── Team Invite Flow Integration Test ─────────────────────────────────────────
#
# Tests the complete lifecycle of a team invitation:
#   1. Owner sends invite → User + UserRole + MerchantMembership created
#   2. Invitee clicks link → shown accept form (valid token)
#   3. Invitee sets password → signed in, redirected to TOTP setup
#   4. Expired / used token → redirected to sign-in with error
#   5. Merchant user cannot assign internal roles (blocked by service + controller)
#   6. Merchant without team.manage is rejected (Pundit)
#
# Note on mail delivery: `deliver_later` goes through Active Job, which in the
# test environment is processed asynchronously. We test the mailer in isolation
# using UserMailer directly rather than asserting ActionMailer::Base.deliveries
# after an HTTP request.

class TeamInviteFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_request(:get, %r{localhost:4000/internal/merchants/.*/kyb-status})
      .to_return(status: 200, body: { status: "not_started" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    @owner = create_merchant_user_with_role("merchant_owner")
  end

  # ── Sending an invitation ──────────────────────────────────────────────────

  test "owner can invite a new merchant_finance user" do
    sign_in @owner

    assert_difference "User.count", 1 do
      assert_difference "UserRole.count", 1 do
        assert_difference "MerchantMembership.count", 1 do
          post team_invite_user_path, params: {
            first_name: "Finance",
            last_name:  "Person",
            email:      "finance.new@merchant.com",
            role_key:   "merchant_finance"
          }
        end
      end
    end

    # Controller redirects to team_users_path on success
    assert_redirected_to team_users_path

    invited = User.find_by!(email: "finance.new@merchant.com")
    assert_equal "merchant_finance", invited.user_roles.first.role_key
    assert_equal DEMO_MERCHANT_CODE, invited.merchant_memberships.first.merchant_code
    assert_equal "invited",          invited.merchant_memberships.first.state
  end

  test "invitation email contains a token link (tests mailer directly)" do
    raw_token, digest = MerchantMembership.generate_invitation_token!
    invitee = User.create!(
      email: "invite-mail-test@merchant.com", first_name: "Mail", last_name: "Test",
      kind: "merchant_user", password: "Password1!xx", otp_required_for_login: false
    )
    membership = MerchantMembership.create!(
      user:                    invitee,
      merchant_code:           DEMO_MERCHANT_CODE,
      merchant_name:           DEMO_MERCHANT_NAME,
      state:                   "invited",
      invited_by:              @owner,
      invitation_token_digest: digest,
      invitation_expires_at:   7.days.from_now
    )

    mail = UserMailer.invitation_instructions(invitee, membership, raw_token)
    body = mail.html_part&.body&.decoded || mail.text_part&.body&.decoded || mail.body.decoded
    assert_match raw_token, body
    assert_match(/invited/i, mail.subject)
    assert_equal [ "invite-mail-test@merchant.com" ], mail.to
  end

  test "inviting an already-registered email redirects back with alert" do
    existing = create_merchant_user_with_role("merchant_support")
    sign_in @owner

    assert_no_difference "User.count" do
      post team_invite_user_path, params: {
        first_name: "Dupe", last_name: "User",
        email:      existing.email, role_key: "merchant_owner"
      }
    end

    # Controller redirects back to team with an alert flash on failure
    assert_redirected_to team_users_path
    follow_redirect!
    assert_match(/already registered/i, response.body)
  end

  test "merchant owner CANNOT invite with an internal role — redirected with alert" do
    sign_in @owner

    assert_no_difference "User.count" do
      post team_invite_user_path, params: {
        first_name: "Staff", last_name: "Person",
        email:      "staff.attempt@merchant.com", role_key: "ops_analyst"
      }
    end

    assert_redirected_to team_users_path
    follow_redirect!
    assert_match(/cannot assign internal roles/i, response.body)
  end

  test "merchant_finance cannot invite team members (no team.manage)" do
    finance = create_merchant_user_with_role("merchant_finance")
    sign_in finance

    post team_invite_user_path, params: {
      first_name: "Sneak", last_name: "Invite",
      email: "sneak@merchant.com", role_key: "merchant_owner"
    }

    assert_forbidden
    assert_equal 0, User.where(email: "sneak@merchant.com").count
  end

  # ── Internal staff invitation (ops_manager inviting internal staff) ───────

  test "ops_manager can invite a new ops_analyst — token stored on user, no MerchantMembership" do
    ops = create_internal_user_with_role("ops_manager")
    sign_in ops

    assert_difference "User.count", 1 do
      assert_difference "UserRole.count", 1 do
        assert_no_difference "MerchantMembership.count" do
          post team_invite_user_path, params: {
            first_name: "New",
            last_name:  "Analyst",
            email:      "new.analyst@yagye.com",
            role_key:   "ops_analyst"
          }
        end
      end
    end

    assert_redirected_to team_users_path

    invited = User.find_by!(email: "new.analyst@yagye.com")
    assert_equal "internal_staff",  invited.kind
    assert_equal "ops_analyst",     invited.user_roles.first.role_key
    assert_not_nil                  invited.invitation_token_digest
    assert_not_nil                  invited.invitation_expires_at
    assert_equal ops,               invited.invited_by
    assert_equal 0,                 invited.merchant_memberships.count
  end

  test "staff invitation email contains a token link (tests mailer directly)" do
    ops     = create_internal_user_with_role("ops_manager")
    invitee = User.create!(
      email: "staff-mail-test@yagye.com", first_name: "Staff", last_name: "Test",
      kind: "internal_staff", password: "Password1!xx", otp_required_for_login: false
    )
    raw_token, digest = User.generate_invitation_token!
    invitee.update!(invitation_token_digest: digest, invitation_expires_at: 7.days.from_now,
                    invited_by: ops)

    mail = UserMailer.staff_invitation_instructions(invitee, ops, raw_token, invitee.invitation_expires_at)
    body = mail.html_part&.body&.decoded || mail.text_part&.body&.decoded || mail.body.decoded
    assert_match raw_token, body
    assert_match(/Yagye/, mail.subject)
    assert_equal [ "staff-mail-test@yagye.com" ], mail.to
  end

  test "staff invitee can view the accept form with a valid token" do
    staff_user, raw_token = create_pending_staff_invitation

    get accept_invitation_path(raw_token)
    assert_ok
    assert_match "Yagye Operations", response.body
  end

  test "staff invitee accepts invitation, is signed in, and redirected to TOTP setup" do
    staff_user, raw_token = create_pending_staff_invitation

    patch accept_invitation_path(raw_token), params: {
      user: { password: "NewSecurePass99!", password_confirmation: "NewSecurePass99!" }
    }

    assert_redirected_to settings_totp_new_path

    staff_user.reload
    assert_nil staff_user.invitation_token_digest
    assert_nil staff_user.invitation_expires_at
  end

  test "expired staff invitation token redirects to sign in" do
    staff_user, raw_token = create_pending_staff_invitation
    staff_user.update!(invitation_expires_at: 1.day.ago)

    get accept_invitation_path(raw_token)
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_match(/invalid or has expired/i, response.body)
  end

  test "staff token cannot be reused after acceptance" do
    staff_user, raw_token = create_pending_staff_invitation

    patch accept_invitation_path(raw_token), params: {
      user: { password: "Password1!xx", password_confirmation: "Password1!xx" }
    }

    get accept_invitation_path(raw_token)
    assert_redirected_to new_user_session_path
  end

  test "ops_manager CANNOT invite a merchant user (no merchant context)" do
    ops = create_internal_user_with_role("ops_manager")
    sign_in ops

    assert_no_difference "User.count" do
      post team_invite_user_path, params: {
        first_name: "Merch", last_name: "User",
        email:      "merch.user@merchant.com", role_key: "merchant_owner"
      }
    end

    assert_redirected_to team_users_path
    follow_redirect!
    assert_match(/merchant context/i, response.body)
  end

  # ── Accepting an invitation ────────────────────────────────────────────────

  test "invitee can view the accept form with a valid token" do
    membership, raw_token = create_pending_invitation

    get accept_invitation_path(raw_token)
    assert_ok
    assert_match DEMO_MERCHANT_NAME, response.body
  end

  test "invitee accepts invitation, is signed in, and redirected to TOTP setup" do
    membership, raw_token = create_pending_invitation

    patch accept_invitation_path(raw_token), params: {
      user: {
        password:              "NewSecurePass99!",
        password_confirmation: "NewSecurePass99!"
      }
    }

    # Redirected to TOTP setup (settings/totp/new) so user sets up 2FA immediately
    assert_redirected_to settings_totp_new_path

    membership.reload
    assert_equal "active",  membership.state
    assert_not_nil          membership.accepted_at
    assert_nil              membership.invitation_token_digest
    assert_nil              membership.invitation_expires_at
  end

  test "accept form rejects a password that is too short (< 12 chars)" do
    membership, raw_token = create_pending_invitation

    patch accept_invitation_path(raw_token), params: {
      user: { password: "Short1!", password_confirmation: "Short1!" }
    }

    assert_equal 422, response.status
    membership.reload
    assert_equal "invited", membership.state
  end

  test "accept form rejects mismatched password confirmation" do
    membership, raw_token = create_pending_invitation

    patch accept_invitation_path(raw_token), params: {
      user: { password: "Password1!xx", password_confirmation: "DifferentPass99!" }
    }

    assert_equal 422, response.status
    membership.reload
    assert_equal "invited", membership.state
  end

  test "expired invitation token redirects to sign in" do
    membership, raw_token = create_pending_invitation
    membership.update!(invitation_expires_at: 1.day.ago)

    get accept_invitation_path(raw_token)
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_match(/invalid or has expired/i, response.body)
  end

  test "invalid token redirects to sign in" do
    get accept_invitation_path("garbage-token-xyz")
    assert_redirected_to new_user_session_path
  end

  test "token cannot be reused after acceptance" do
    membership, raw_token = create_pending_invitation

    patch accept_invitation_path(raw_token), params: {
      user: { password: "Password1!xx", password_confirmation: "Password1!xx" }
    }

    # Try to use the same token again
    get accept_invitation_path(raw_token)
    assert_redirected_to new_user_session_path
  end

  private

  def create_pending_staff_invitation
    ops = create_internal_user_with_role("ops_manager")
    raw_token, digest = User.generate_invitation_token!
    staff_user = User.create!(
      email:                   "staff-invitee-#{SecureRandom.hex(4)}@yagye.com",
      first_name:              "Staff",
      last_name:               "Invitee",
      kind:                    "internal_staff",
      password:                SecureRandom.hex(16),
      otp_required_for_login:  false,
      invited_by:              ops,
      invitation_token_digest: digest,
      invitation_expires_at:   7.days.from_now
    )
    role = Role.find_by!(key: "ops_analyst")
    UserRole.create!(user: staff_user, role: role, granted_by: ops, granted_at: Time.current)
    [ staff_user, raw_token ]
  end

  def create_pending_invitation
    raw_token, digest = MerchantMembership.generate_invitation_token!
    invitee = User.create!(
      email:                  "invitee-#{SecureRandom.hex(4)}@merchant.com",
      first_name:             "Invitee",
      last_name:              "User",
      kind:                   "merchant_user",
      password:               SecureRandom.hex(16),
      otp_required_for_login: false
    )
    role = Role.find_by!(key: "merchant_finance")
    UserRole.create!(
      user:          invitee,
      role:          role,
      granted_by:    @owner,
      granted_at:    Time.current,
      merchant_code: DEMO_MERCHANT_CODE
    )
    membership = MerchantMembership.create!(
      user:                    invitee,
      merchant_code:           DEMO_MERCHANT_CODE,
      merchant_name:           DEMO_MERCHANT_NAME,
      state:                   "invited",
      invited_by:              @owner,
      invitation_token_digest: digest,
      invitation_expires_at:   7.days.from_now
    )
    [ membership, raw_token ]
  end
end
