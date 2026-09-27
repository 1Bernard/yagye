# frozen_string_literal: true

module Merchants
  class MerchantsController < ApplicationController
    def index
      authorize :merchants, :index?
      scope = Merchants::MerchantsQuery.new.call(filters)
      pagy, merchants = pagy(scope, limit: 25)
      render Merchants::IndexView.new(
        merchants: merchants, pagy: pagy,
        status: params[:status], query: params[:q], country: params[:country],
        from: params[:from], to: params[:to],
        view: params[:view].presence_in(%w[list grid]) || "list",
        stats: merchant_stats,
        mtd_volumes: mtd_volumes(merchants)
      )
    end

    def filter
      authorize :merchants, :index?
      render Merchants::FilterView.new(
        query:   params[:q],
        status:  params[:status],
        country: params[:country],
        from:    params[:from],
        to:      params[:to]
      )
    end

    def show
      authorize :merchants, :show?
      application = decode_id(PortalMerchantApplication)

      beneficial_owners = []
      documents         = []
      screening         = nil

      if (mc = application.merchant_code).present?
        client = CoreApiClient.new
        ubos_r     = client.list_beneficial_owners(mc)
        docs_r     = client.list_kyb_documents(mc)
        screening_r = client.merchant_screening_status(mc)

        beneficial_owners = ubos_r.success?     ? (ubos_r.body["data"]     || []) : []
        documents         = docs_r.success?     ? (docs_r.body["data"]     || []) : []
        screening         = screening_r.success? ? screening_r.body              : nil
      end

      render Merchants::ShowView.new(
        application:       application,
        beneficial_owners: beneficial_owners,
        documents:         documents,
        screening:         screening
      )
    end

    def update
      authorize :merchants, :update?
      application = decode_id(PortalMerchantApplication)
      new_status  = params[:status].to_s.strip
      client      = CoreApiClient.new

      result =
        case new_status
        when "approved"
          client.approve_application(
            application.merchant_code || application.application_code,
            approved_by: current_user.user_code
          )
        when "rejected"
          client.reject_application(
            application.application_code,
            rejected_by: current_user.user_code,
            reason: params[:reason].presence || "Rejected by ops"
          )
        when "suspended"
          client.suspend_merchant(application.merchant_code, suspended_by: current_user.user_code)
        when "active"
          client.reactivate_merchant(application.merchant_code, reactivated_by: current_user.user_code)
        else
          return redirect_to(merchant_path(application), alert: "Unknown status: #{new_status}")
        end

      if result.success?
        application.update_column(:status, new_status == "active" ? "approved" : new_status)
        redirect_to merchant_path(application), notice: "Merchant #{new_status.humanize}."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end

    def kyb_approve
      authorize :merchants, :kyb_approve?
      application = decode_id(PortalMerchantApplication)
      unless application.merchant_code.present?
        return redirect_to merchant_path(application),
                           alert: "No merchant account linked — approve the application first."
      end
      result = CoreApiClient.new.approve_merchant_kyb(
        application.merchant_code,
        approved_by: current_user.user_code
      )
      if result.success?
        redirect_to merchant_path(application),
                    notice: "KYB approved. Merchant is now live and can process payments."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end

    private

    def filters
      params.permit(:status, :q, :country, :from, :to).to_h.symbolize_keys
    end

    def mtd_volumes(merchants)
      codes = merchants.filter_map(&:merchant_code)
      Payments::MtdVolumesQuery.new.call(merchant_codes: codes)
    end

    def merchant_stats
      all = PortalMerchantApplication.all
      {
        active:       all.where(status: "approved").count,
        pending_kyb:  all.where(status: %w[submitted under_review]).count,
        suspended:    all.where(status: "suspended").count,
        onboarded_30d: all.where(status: "approved")
                          .where("last_applied_at >= ?", 30.days.ago).count
      }
    end
  end
end
