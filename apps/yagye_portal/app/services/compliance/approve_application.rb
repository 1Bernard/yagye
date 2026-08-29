# frozen_string_literal: true

module Compliance
  # Sends an approval disposition to Core via the internal API.
  # Core validates the state transition, emits MerchantKybApproved,
  # and the Karafka consumer updates the portal read model.
  # The portal never writes directly to portal_merchant_applications.
  class ApproveApplication
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(application:, approved_by:, request: nil)
      @application = application
      @approved_by = approved_by
      @request     = request
    end

    def call
      unless @approved_by.internal_staff?
        audit_log(action: "kyb.disposition_approved", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "attempted",
                  metadata: { reason: "unauthorized" })
        return Result.new(success?: false, error: "Only Yagye staff may approve KYB applications")
      end

      result = CoreApiClient.new.approve_application(
        @application.application_code,
        approved_by: @approved_by.email
      )

      if result.success?
        audit_log(action: "kyb.disposition_approved", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "succeeded")
        Result.new(success?: true)
      else
        audit_log(action: "kyb.disposition_approved", resource_type: "PortalMerchantApplication",
                  resource_code: @application.application_code, outcome: "failed",
                  metadata: { error_code: result.error_code, error: result.error_message })
        Result.new(success?: false, error: result.error_message)
      end
    end
  end
end
