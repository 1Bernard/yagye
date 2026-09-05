# frozen_string_literal: true

module Compliance
  class KybReviewsController < ApplicationController
    def index
      authorize :kyb_reviews, :index?
      tab          = params[:tab].presence_in(%w[pending in_review approved rejected]) || "pending"
      applications = Compliance::ApplicationsQuery.new.call(tab: tab)
      render KybReviews::IndexView.new(tab: tab, applications: applications)
    end

    def show
      authorize :kyb_reviews, :show?
      application = decode_id(PortalMerchantApplication)
      render KybReviews::ShowView.new(application: application)
    end

    def approve
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      result = Compliance::ApproveApplication.new.call(
        application_code: application.application_code,
        approved_by:      current_user.email
      )
      if result.success?
        redirect_to kyb_review_path(application), notice: "Application approved."
      else
        redirect_to kyb_review_path(application), alert: result.error_message
      end
    end

    def reject
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      result = Compliance::RejectApplication.new.call(
        application_code: application.application_code,
        rejected_by:      current_user.email,
        reason:           params[:reason].to_s.strip.presence || "No reason provided."
      )
      if result.success?
        redirect_to kyb_review_path(application), notice: "Application rejected."
      else
        redirect_to kyb_review_path(application), alert: result.error_message
      end
    end
  end
end
