# frozen_string_literal: true

require "test_helper"
require "support/integration_helpers"

# ── Authentication Integration Test ───────────────────────────────────────────
#
# Verifies the sign-in flows end-to-end:
#
# All users go through a two-step auth flow (as required for a PSP):
#   Step 1: email + password → POST /users/sign_in
#   Step 2: OTP code        → POST /users/otp-challenge
#
# Non-TOTP merchant users receive an email OTP at step 2.
# TOTP-enrolled users use their authenticator app at step 2.
# Internal staff without TOTP are sent to TOTP enrollment.
#
# The Devise::Test::IntegrationHelpers `sign_in` method bypasses this flow
# and is used by RBAC/feature tests that care about authorization, not auth.

class AuthenticationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers
  include WebMock::API

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @user = create_merchant_user_with_role("merchant_owner")
  end

  # ── Step 1: password → OTP challenge ───────────────────────────────────────

  test "merchant user with valid password is redirected to OTP challenge (email OTP)" do
    post user_session_path, params: {
      user: { email: @user.email, password: "Password1!xx" }
    }

    # All merchant users go through email OTP (two-step auth)
    assert_redirected_to users_otp_challenge_path
  end

  test "TOTP-enrolled user is also redirected to OTP challenge (TOTP)" do
    @user.update!(
      otp_required_for_login: true,
      otp_secret:             ROTP::Base32.random
    )

    post user_session_path, params: {
      user: { email: @user.email, password: "Password1!xx" }
    }

    assert_redirected_to users_otp_challenge_path
  end

  test "internal staff without TOTP are redirected to TOTP enrollment" do
    ops = create_internal_user_with_role("ops_manager")
    post user_session_path, params: {
      user: { email: ops.email, password: "Password1!xx" }
    }

    assert_redirected_to users_totp_enrollment_path
  end

  # ── Step 1: failed password ─────────────────────────────────────────────────

  test "wrong password returns 422 and stays on sign-in page" do
    post user_session_path, params: {
      user: { email: @user.email, password: "WrongPassword1!" }
    }

    assert_equal 422, response.status
    assert_match(/invalid email or password/i, response.body)
  end

  test "unknown email returns 422" do
    post user_session_path, params: {
      user: { email: "nobody@nowhere.com", password: "Password1!xx" }
    }

    assert_equal 422, response.status
  end

  # ── Signed-in state (using Devise helper to skip OTP) ──────────────────────

  test "signed-in merchant user reaches dashboard" do
    stub_kyb_status
    sign_in @user
    get authenticated_root_path
    assert_ok
  end

  test "signed-in internal staff reaches dashboard" do
    ops = create_internal_user_with_role("ops_manager")
    sign_in ops
    get authenticated_root_path
    assert_ok
  end

  test "signed-out user is redirected to sign in page on any protected route" do
    get payments_path
    assert_redirected_to new_user_session_path
  end

  test "signed-out POST is redirected to sign in" do
    dispute = create_open_dispute
    post dispute_evidence_draft_path(dispute), params: { evidence_text: "test" }
    assert_redirected_to new_user_session_path
  end

  # ── Session management ─────────────────────────────────────────────────────

  test "sign out invalidates session and protects subsequent requests" do
    sign_in @user
    delete destroy_user_session_path
    follow_redirect!

    get payments_path
    assert_redirected_to new_user_session_path
  end

  test "keepalive returns ok for authenticated users" do
    sign_in @user
    post session_keepalive_path, as: :json
    assert_includes [ 200, 204 ], response.status
  end

  # ── Password policy (unit-level, fast) ─────────────────────────────────────

  test "password must be at least 12 characters" do
    u = User.new(email: "pw-test@example.com", first_name: "A", last_name: "B",
                 kind: "merchant_user", password: "Short1!")
    assert_not u.valid?
    assert_includes u.errors[:password], "is too short (minimum is 12 characters)"
  end

  test "password of exactly 12 characters is valid" do
    u = User.new(email: "pw-test2@example.com", first_name: "A", last_name: "B",
                 kind: "merchant_user", password: "Password1!xx")
    u.valid?
    assert_empty u.errors[:password]
  end
end
