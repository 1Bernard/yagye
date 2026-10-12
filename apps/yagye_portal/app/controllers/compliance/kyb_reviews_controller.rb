# frozen_string_literal: true

module Compliance
  class KybReviewsController < ApplicationController
    def index
      authorize :kyb_reviews, :index?
      tab   = params[:tab].presence_in(%w[pending in_review approved rejected]) || "pending"
      scope = Compliance::ApplicationsQuery.new.call(
        tab:               tab,
        q:                 params[:q],
        from:              params[:from],
        to:                params[:to],
        reviewer:          params[:reviewer].presence_in(%w[unassigned mine]),
        current_user_code: current_user.user_code
      )
      pagy, applications = pagy(scope, limit: 25)
      render KybReviews::IndexView.new(
        tab: tab, applications: applications, pagy: pagy,
        query: params[:q], from: params[:from], to: params[:to],
        reviewer: params[:reviewer].presence_in(%w[unassigned mine]),
        view: params[:view].presence_in(%w[list grid]) || "list",
        stats: review_stats, mtd_volumes: mtd_volumes(applications)
      )
    end

    def filter
      authorize :kyb_reviews, :index?
      tab = params[:tab].presence_in(%w[pending in_review approved rejected]) || "pending"
      render KybReviews::FilterView.new(
        tab:      tab,
        query:    params[:q],
        from:     params[:from],
        to:       params[:to],
        reviewer: params[:reviewer].presence_in(%w[unassigned mine]),
        view:     params[:view].presence_in(%w[list grid]) || "list"
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
      result = Compliance::ApproveApplication.new(
        application: application,
        approved_by: current_user
      ).call
      if result.success?
        KybMailer.approved(application).deliver_later if application.submitted_by_email.present?
        redirect_to kyb_review_path(application), notice: "Application approved."
      else
        redirect_to kyb_review_path(application), alert: result.error
      end
    end

    def reject
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      reason = params[:reason].to_s.strip.presence || "No reason provided."
      result = Compliance::RejectApplication.new(
        application: application,
        rejected_by: current_user,
        reason:      reason
      ).call
      if result.success?
        KybMailer.rejected(application, reason: reason).deliver_later if application.submitted_by_email.present?
        redirect_to kyb_review_path(application), notice: "Application rejected."
      else
        redirect_to kyb_review_path(application), alert: result.error
      end
    end

    def assign
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      application.update!(reviewed_by: current_user.user_code, status: "under_review")
      if application.merchant_code.present?
        CoreApiClient.new.start_review(application.merchant_code,
                                       reviewed_by: current_user.user_code)
      end
      redirect_to kyb_reviews_path(tab: "in_review"), notice: "Assigned to #{current_user.full_name}."
    end

    def download_document
      authorize :kyb_reviews, :show?
      result = CoreApiClient.new.get_document_download_url(params[:document_id])
      if result.success?
        redirect_to result.body["url"], allow_other_host: true
      else
        redirect_to kyb_review_path(params[:id]), alert: "Document not available."
      end
    end

    def approve_modal
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      render KybReviews::ApproveModalView.new(application: application)
    end

    def reject_modal
      authorize :kyb_reviews, :show?
      application = decode_id(PortalMerchantApplication)
      render KybReviews::RejectModalView.new(application: application)
    end

    def add_ubo_modal
      authorize :kyb_reviews, :show?
      application = decode_id(PortalMerchantApplication)
      render KybReviews::AddUboModalView.new(application: application)
    end

    def grant_live_modal
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:        "Activate live mode",
        body:         "#{application.legal_name} will be able to process real transactions immediately.",
        warning_note: "Only activate after KYB tier 3+ has been confirmed and all compliance checks are cleared.",
        confirm_path: grant_live_kyb_review_path(application),
        confirm_label: "Activate live mode",
        success:      true
      )
    end

    def reject_document_modal
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      doc_id      = params[:document_id]
      render UI::ConfirmModal.new(
        title:          "Reject document",
        body:           "This document will be marked as rejected. The merchant will need to re-upload.",
        confirm_path:   kyb_review_document_review_path(application, doc_id),
        confirm_method: "patch",
        confirm_label:  "Reject document",
        danger:         true,
        hidden_fields:  { status: "rejected" }
      )
    end

    def add_ubo
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      unless application.merchant_code.present?
        return redirect_to kyb_review_path(application), alert: "Merchant not yet registered in Core."
      end

      ownership_bps = (params[:ownership_pct].to_f * 100).round.clamp(0, 10_000)
      subject_ref   = SecureRandom.uuid
      result = CoreApiClient.new.add_beneficial_owner(
        application.merchant_code,
        subject_ref:   subject_ref,
        role:          params[:role].to_s.presence_in(%w[director ubo both]) || "ubo",
        ownership_bps: ownership_bps,
        subject_name:  params[:subject_name].to_s.strip.presence,
        subject_dob:   params[:subject_dob].to_s.strip.presence
      )
      if result.success?
        redirect_to kyb_review_path(application), notice: "Beneficial owner added."
      else
        redirect_to kyb_review_path(application), alert: result.error_message
      end
    end

    def review_document
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      status = params[:status].to_s.presence_in(%w[under_review approved rejected])
      unless status
        return redirect_to kyb_review_path(application), alert: "Invalid review status."
      end
      result = CoreApiClient.new.review_kyb_document(
        application.merchant_code,
        params[:document_id],
        status:         status,
        reviewer_code:  current_user.user_code,
        reviewer_notes: params[:reviewer_notes].presence
      )
      if result.success?
        label = { "under_review" => "marked for review", "approved" => "approved",
                  "rejected" => "rejected" }.fetch(status, status)
        redirect_to kyb_review_path(application), notice: "Document #{label}."
      else
        redirect_to kyb_review_path(application), alert: result.error_message
      end
    end

    def grant_live
      authorize :kyb_reviews, :approve?
      application = decode_id(PortalMerchantApplication)
      unless application.merchant_code.present?
        return redirect_to kyb_review_path(application), alert: "Merchant not yet registered in Core."
      end
      result = CoreApiClient.new.approve_merchant_kyb(application.merchant_code,
                                                       approved_by: current_user.user_code)
      if result.success?
        redirect_to kyb_review_path(application),
                    notice: "Live mode activated for #{application.legal_name}."
      else
        redirect_to kyb_review_path(application), alert: result.error_message
      end
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
      codes = applications.filter_map(&:merchant_code)
      Payments::MtdVolumesQuery.new.call(merchant_codes: codes)
    end
  end
end
