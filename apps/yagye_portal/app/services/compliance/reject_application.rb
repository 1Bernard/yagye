# frozen_string_literal: true

module Compliance
  class RejectApplication
    include Auditable

    Result = Struct.new(:success?, :application, :error, keyword_init: true)

    def initialize(application:, rejected_by:, reason:, request: nil)
      @application = application
      @rejected_by = rejected_by
      @reason      = reason.to_s.strip
      @request     = request
    end

    def call
      unless @rejected_by.internal_staff?
        return Result.new(success?: false, error: "Only Yagye staff may reject KYB applications")
      end
      if @reason.blank?
        return Result.new(success?: false, error: "A rejection reason is required")
      end
      unless @application.status.in?(%w[submitted under_review])
        return Result.new(success?: false, error: "Application is already #{@application.status}")
      end

      @application.update!(
        status:          "rejected",
        reviewed_by:     @rejected_by.email,
        rejected_reason: @reason
      )

      # TODO P13: publish MerchantKybRejected event → Core via Outbox/Kafka

      audit_log(action: "kyb.disposition_rejected", resource_type: "PortalMerchantApplication",
                resource_code: @application.application_code, outcome: "succeeded",
                reason: @reason)
      Result.new(success?: true, application: @application)
    rescue ActiveRecord::RecordInvalid => e
      audit_log(action: "kyb.disposition_rejected", resource_type: "PortalMerchantApplication",
                resource_code: @application.application_code, outcome: "failed",
                metadata: { error: e.message })
      Result.new(success?: false, error: e.message)
    end
  end
end
