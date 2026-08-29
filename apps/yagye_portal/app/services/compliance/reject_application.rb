# frozen_string_literal: true

module Compliance
  class RejectApplication
    Result = Struct.new(:success?, :application, :error, keyword_init: true)

    def initialize(application:, rejected_by:, reason:)
      @application = application
      @rejected_by = rejected_by
      @reason      = reason.to_s.strip
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

      Result.new(success?: true, application: @application)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
