# frozen_string_literal: true

require "test_helper"
require "support/core_api_stubs"

module Compliance
  class RejectApplicationTest < ActiveSupport::TestCase
    include CoreApiStubs

    setup do
      @application = create(:portal_merchant_application, status: "under_review")
      @staff       = create(:internal_staff_user)
      @merchant    = create(:merchant_user)
    end

    # ── Authorization ─────────────────────────────────────────────────────────

    test "merchant user cannot reject an application" do
      result = call(rejected_by: @merchant, reason: "Missing documents")

      refute result.success?
      assert_equal "Only Yagye staff may reject KYB applications", result.error
    end

    # ── Input validation ──────────────────────────────────────────────────────

    test "blank reason returns failure without calling Core" do
      # No stub — an HTTP call would raise WebMock::NetConnectNotAllowedError
      result = call(rejected_by: @staff, reason: "")

      refute result.success?
      assert_equal "A rejection reason is required", result.error
    end

    test "whitespace-only reason is treated as blank" do
      result = call(rejected_by: @staff, reason: "   ")

      refute result.success?
      assert_equal "A rejection reason is required", result.error
    end

    # ── Happy path ────────────────────────────────────────────────────────────

    test "staff user with valid reason succeeds when Core returns 200" do
      stub_core_reject(application_code: @application.application_code)

      result = call(rejected_by: @staff, reason: "Forged director ID")

      assert result.success?
    end

    test "successful rejection is recorded in the audit log with the reason" do
      stub_core_reject(application_code: @application.application_code)

      assert_difference "AuditLog.count", 1 do
        call(rejected_by: @staff, reason: "Forged director ID")
      end

      log = AuditLog.last
      assert_equal "kyb.disposition_rejected", log.action
      assert_equal "succeeded",               log.outcome
      assert_equal "Forged director ID",      log.reason
    end

    # ── Core returns an error ─────────────────────────────────────────────────

    test "returns failure when Core returns a non-2xx response" do
      stub_core_reject(application_code: @application.application_code, success: false)

      result = call(rejected_by: @staff, reason: "Forged director ID")

      refute result.success?
      assert_includes result.error, "Application cannot be rejected"
    end

    private

    def call(rejected_by:, reason:)
      Compliance::RejectApplication.new(
        application: @application,
        rejected_by: rejected_by,
        reason:      reason
      ).call
    end
  end
end
