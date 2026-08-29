# frozen_string_literal: true

module Compliance
  # Sends a rejection disposition to Core via the internal API.
  # Core validates the state transition, emits MerchantKybRejected,
  # and the Karafka consumer updates the portal read model.
  # The portal never writes directly to portal_merchant_applications.
  class RejectApplication
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(application:, rejected_by:, reason:, request: nil)
      @application = application
      @rejected_by = rejected_by
      @reason      = reason.to_s.strip
      @request     = request
    end

    def call
      unless @rejected_by.internal_staff?
        audit_log(action: "kyb.disposition_rejected", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "attempted",
                  metadata: { reason: "unauthorized" })
        return Result.new(success?: false, error: "Only Yagye staff may reject KYB applications")
      end

      if @reason.blank?
        return Result.new(success?: false, error: "A rejection reason is required")
      end

      result = CoreApiClient.new.reject_application(
        @application.application_code,
        rejected_by: @rejected_by.email,
        reason:      @reason
      )

      if result.success?
        audit_log(action: "kyb.disposition_rejected", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "succeeded",
                  reason: @reason)
        Result.new(success?: true)
      else
        audit_log(action: "kyb.disposition_rejected", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "failed",
                  metadata: { error_code: result.error_code, error: result.error_message })
        Result.new(success?: false, error: result.error_message)
      end
    end
  end
end
