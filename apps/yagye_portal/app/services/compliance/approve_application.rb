# frozen_string_literal: true

module Compliance
  class ApproveApplication
    Result = Struct.new(:success?, :application, :error, keyword_init: true)

    def initialize(application:, approved_by:)
      @application = application
      @approved_by = approved_by
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

      Result.new(success?: true, application: @application)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
