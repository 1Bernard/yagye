# frozen_string_literal: true

# Shared helpers for ActionDispatch::IntegrationTest cases.
#
# Include at the class level:
#
#   class MyTest < ActionDispatch::IntegrationTest
#     include IntegrationHelpers
#   end
module IntegrationHelpers
  # Devise::Test::IntegrationHelpers must be included in the test class itself
  # (it calls `setup`, which only works in a class, not a plain module).
  # Each integration test class includes it directly.

  DEMO_MERCHANT_CODE = "MCH-INTTEST"
  DEMO_MERCHANT_NAME = "Integration Test Merchant Ltd"

  # ── User creation ───────────────────────────────────────────────────────────

  # Creates a merchant user with a single role in the shared test merchant.
  def create_merchant_user_with_role(role_key, email: nil)
    email ||= "#{role_key.tr('_', '-')}-#{SecureRandom.hex(4)}@merchant-test.com"
    user = User.create!(
      email:                email,
      first_name:           role_key.split("_").first.capitalize,
      last_name:            "Tester",
      kind:                 "merchant_user",
      password:             "Password1!xx",
      otp_required_for_login: false
    )
    MerchantMembership.create!(
      user:          user,
      merchant_code: DEMO_MERCHANT_CODE,
      merchant_name: DEMO_MERCHANT_NAME,
      state:         "active"
    )
    role = Role.find_by!(key: role_key)
    UserRole.create!(
      user:          user,
      role:          role,
      granted_by:    user,
      granted_at:    Time.current,
      merchant_code: DEMO_MERCHANT_CODE
    )
    user
  end

  # Creates an internal staff user with a single role.
  def create_internal_user_with_role(role_key, email: nil)
    email ||= "#{role_key.tr('_', '-')}-#{SecureRandom.hex(4)}@yagye-test.com"
    user = User.create!(
      email:                email,
      first_name:           role_key.split("_").first.capitalize,
      last_name:            "Internal",
      kind:                 "internal_staff",
      password:             "Password1!xx",
      otp_required_for_login: false
    )
    role = Role.find_by!(key: role_key)
    UserRole.create!(
      user:       user,
      role:       role,
      granted_by: user,
      granted_at: Time.current
    )
    user
  end

  # ── Dispute factory ─────────────────────────────────────────────────────────

  # Creates an open dispute for DEMO_MERCHANT_CODE.
  def create_open_dispute(merchant_code: DEMO_MERCHANT_CODE, **attrs)
    Dispute.create!({
      core_dispute_id: "disp_#{SecureRandom.hex(8)}",
      reference:       "REF-#{SecureRandom.hex(6).upcase}",
      merchant_code:   merchant_code,
      status:          "under_review",
      amount:          5000,
      currency:        "GHS",
      reason:          "fraud",
      customer_msisdn: "233241000001",
      last_event_id:   SecureRandom.uuid,
      last_applied_at: Time.current
    }.merge(attrs))
  end

  # ── Core API stubs ──────────────────────────────────────────────────────────

  CORE_API_URL = ENV.fetch("CORE_API_URL", "http://localhost:4000")

  # Stubs the KYB status check that the dashboard calls for every merchant user.
  # Must be called before any GET to a page that triggers load_kyb_banner_progress.
  def stub_kyb_status(merchant_code = DEMO_MERCHANT_CODE, status: "not_started")
    stub_request(:get, "#{CORE_API_URL}/internal/merchants/#{merchant_code}/kyb-status")
      .to_return(
        status: 200,
        body:   { status: status, completeness: 0 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # ── Assertion helpers ───────────────────────────────────────────────────────

  # Asserts the last response was a Pundit not-authorized redirect to root.
  # In integration tests response.location is a full URL, so we parse the path.
  def assert_forbidden
    assert_includes [ 302, 303 ], response.status,
      "Expected forbidden redirect but got #{response.status} (#{response.location})"
    path = URI.parse(response.location).path
    assert_equal "/", path,
      "Expected redirect to root (/), got #{response.location}"
  end

  # Asserts the route returned a successful HTML response.
  def assert_ok
    assert_equal 200, response.status,
      "Expected 200 but got #{response.status}. Body snippet: #{response.body[0, 200]}"
  end
end
