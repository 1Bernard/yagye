# frozen_string_literal: true

require "test_helper"
require "support/core_api_stubs"

module Compliance
  class ApproveApplicationTest < ActiveSupport::TestCase
    include CoreApiStubs

    setup do
      @application = create(:portal_merchant_application, status: "under_review")
      @staff       = create(:internal_staff_user)
      @merchant    = create(:merchant_user)
    end

    # ── Authorization ─────────────────────────────────────────────────────────

    test "merchant user cannot approve an application" do
      result = call(approved_by: @merchant)

      refute result.success?
      assert_equal "Only Yagye staff may approve KYB applications", result.error
    end

    test "merchant user attempt is recorded in the audit log" do
      assert_difference "AuditLog.count", 1 do
        call(approved_by: @merchant)
      end

      log = AuditLog.last
      assert_equal "kyb.disposition_approved", log.action
      assert_equal "attempted",                log.outcome
    end

    # ── Happy path ────────────────────────────────────────────────────────────

    test "staff user succeeds when Core returns 200" do
      stub_core_approve(application_code: @application.application_code)

      result = call(approved_by: @staff)

      assert result.success?
      assert_nil result.error
    end

    test "successful approval is recorded in the audit log" do
      stub_core_approve(application_code: @application.application_code)

      assert_difference "AuditLog.count", 1 do
        call(approved_by: @staff)
      end

      log = AuditLog.last
      assert_equal "kyb.disposition_approved",           log.action
      assert_equal "succeeded",                          log.outcome
      assert_equal @application.application_code.to_s,  log.resource_code
    end

    # ── Core returns an error ─────────────────────────────────────────────────

    test "returns failure when Core returns a non-2xx response" do
      stub_core_approve(application_code: @application.application_code, success: false)

      result = call(approved_by: @staff)

      refute result.success?
      assert_includes result.error, "Application cannot be approved"
    end

    test "Core error is recorded in the audit log" do
      stub_core_approve(application_code: @application.application_code, success: false)

      assert_difference "AuditLog.count", 1 do
        call(approved_by: @staff)
      end

      log = AuditLog.last
      assert_equal "failed",     log.outcome
      assert_equal "invalid_state_transition", log.metadata["error_code"]
    end

    # ── Network failure ────────────────────────────────────────────────────────

    test "returns failure when Core is unreachable" do
      stub_core_timeout(
        "#{CoreApiStubs::CORE_API_URL}/internal/applications/#{@application.application_code}/approve"
      )

      # Faraday retry fires 2 more times on timeout — we need 3 stubs total.
      # WebMock's stub_request matches all calls to the URL, so one stub covers all retries.
      result = call(approved_by: @staff)

      refute result.success?
      assert result.error.present?
    end

    private

    def call(approved_by:)
      Compliance::ApproveApplication.new(
        application: @application,
        approved_by: approved_by
      ).call
    end
  end
end
