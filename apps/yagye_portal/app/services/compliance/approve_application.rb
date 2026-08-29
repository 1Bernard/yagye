# frozen_string_literal: true

module Compliance
  class ApproveApplication
    include Auditable

    Result = Struct.new(:success?, :application, :error, keyword_init: true)

    def initialize(application:, approved_by:, request: nil)
      @application = application
      @approved_by = approved_by
      @request     = request
    end

    def call
      unless @approved_by.internal_staff?
        return Result.new(success?: false, error: "Only Yagye staff may approve KYB applications")
      end

      unless @application.status.in?(%w[submitted under_review])
        return Result.new(success?: false, error: "Application is already #{@application.status}")
      end

      @application.update!(status: "approved", approved_by: @approved_by.email)

      # TODO P13: publish MerchantKybApproved event → Core via Outbox/Kafka

      audit_log(action: "kyb.disposition_approved", resource_type: "PortalMerchantApplication",
                resource_code: @application.application_code, outcome: "succeeded")
      Result.new(success?: true, application: @application)
    rescue ActiveRecord::RecordInvalid => e
      audit_log(action: "kyb.disposition_approved", resource_type: "PortalMerchantApplication",
                resource_code: @application.application_code, outcome: "failed",
                metadata: { error: e.message })
      Result.new(success?: false, error: e.message)
    end
  end
end
