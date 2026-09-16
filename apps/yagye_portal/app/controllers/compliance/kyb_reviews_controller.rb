# frozen_string_literal: true

module Compliance
  class KybReviewsController < ApplicationController
    def index
      authorize :kyb_reviews, :index?
      tab          = params[:tab].presence_in(%w[pending in_review approved rejected]) || "pending"
      pagy, applications = pagy(Compliance::ApplicationsQuery.new.call(tab: tab), limit: 25)
      render KybReviews::IndexView.new(
        tab: tab, applications: applications, pagy: pagy,
        stats: review_stats, mtd_volumes: mtd_volumes(applications)
      )
    end

    def show
      authorize :kyb_reviews, :show?
      application = decode_id(PortalMerchantApplication)

      beneficial_owners = []
      documents         = []
      screening         = nil

      if (mc = application.merchant_code).present?
        client              = CoreApiClient.new
        ubos_r              = client.list_beneficial_owners(mc)
        docs_r              = client.list_kyb_documents(mc)
        screening_r         = client.merchant_screening_status(mc)
        beneficial_owners   = ubos_r.success?      ? (ubos_r.body["data"]     || []) : []
        documents           = docs_r.success?      ? (docs_r.body["data"]     || []) : []
        screening           = screening_r.success? ? screening_r.body              : nil
      end

      render KybReviews::ShowView.new(
        application:       application,
        beneficial_owners: beneficial_owners,
        documents:         documents,
        screening:         screening
      )
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

    def assign
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      application.update!(reviewed_by: current_user.email, status: "under_review")
      redirect_to kyb_reviews_path(tab: "in_review"), notice: "Assigned to #{current_user.email}."
    end

    private

    def review_stats
      all = PortalMerchantApplication.all
      {
        pending:      all.where(status: "submitted").count,
        in_review:    all.where(status: "under_review").count,
        approved_30d: all.where(status: "approved").where("last_applied_at >= ?", 30.days.ago).count,
        rejected_30d: all.where(status: "rejected").where("last_applied_at >= ?", 30.days.ago).count
      }
    end

    def mtd_volumes(applications)
      codes = applications.filter_map(&:merchant_code).uniq
      return {} if codes.empty?

      Payment
        .where(merchant_code: codes, status: "paid")
        .where("created_at >= ?", Time.current.beginning_of_month)
        .group(:merchant_code)
        .sum(:amount)
    end
  end
end
