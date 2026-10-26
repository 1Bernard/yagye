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
      application = find_owned!(PortalMerchantApplication)

      beneficial_owners = []
      documents         = []
      payout_dests      = []
      screening         = nil
      reserve_policy    = nil
      pricing_plan      = nil

      if (mc = application.merchant_code).present?
        client = CoreApiClient.new
        ubos_r      = client.list_beneficial_owners(mc)
        docs_r      = client.list_kyb_documents(mc)
        screening_r = client.get_merchant_screening_status(mc)
        reserves_r  = client.list_merchant_reserves(mc)
        plan_r      = client.get_merchant_pricing_plan(mc)
        dests_r     = client.list_payout_destinations(mc)

        beneficial_owners = ubos_r.success?     ? (ubos_r.body["data"] || []) : []
        documents         = docs_r.success?     ? (docs_r.body["data"] || []) : []
        screening         = screening_r.success? ? screening_r.body            : nil
        if reserves_r.success? && (pol = reserves_r.body["policy"])
          pol["created_by"]  = resolve_user_display(pol["created_by"])
          pol["approved_by"] = resolve_user_display(pol["approved_by"])
          reserve_policy = pol
        end
        pricing_plan      = plan_r.success?      ? plan_r.body                 : nil
        payout_dests      = dests_r.success?     ? (dests_r.body["data"] || []) : []
      end

      application.reviewed_by = resolve_user_display(application.reviewed_by)
      application.approved_by = resolve_user_display(application.approved_by)

      render Merchants::ShowView.new(
        application:       application,
        beneficial_owners: beneficial_owners,
        documents:         documents,
        screening:         screening,
        reserve_policy:    reserve_policy,
        pricing_plan:      pricing_plan,
        payout_dests:      payout_dests
      )
    end

    def assign_pricing_plan_modal
      authorize :merchants, :update?
      application    = find_owned!(PortalMerchantApplication)
      plans_r        = CoreApiClient.new.list_pricing_plans
      available_plans = plans_r.success? ? (plans_r.body["data"] || []) : []
      render Merchants::AssignPricingPlanModalView.new(application: application, plans: available_plans)
    end

    def assign_pricing_plan
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
      plan_id     = params[:plan_id].to_s.strip

      if plan_id.blank?
        return redirect_to merchant_path(application), alert: "Please select a plan."
      end

      result = CoreApiClient.new.assign_merchant_pricing_plan(application.merchant_code, plan_id)

      if result.success?
        redirect_to merchant_path(application), notice: "Pricing plan updated."
      else
        redirect_to merchant_path(application), alert: result.error_message || "Could not assign pricing plan."
      end
    end

    def update
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
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
      application = find_owned!(PortalMerchantApplication)
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

    def kyb_approve_modal
      authorize :merchants, :kyb_approve?
      application = find_owned!(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:         "Complete KYB approval",
        body:          "#{application.legal_name} will go live and can process real payments immediately.",
        warning_note:  "Ensure all KYB documents and beneficial owner checks are complete before approving.",
        confirm_path:  kyb_approve_merchant_path(application),
        confirm_label: "Complete KYB approval",
        success:       true
      )
    end

    def approve_modal
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:          "Approve application",
        body:           "A merchant account will be created for #{application.legal_name}.",
        confirm_path:   merchant_path(application),
        confirm_method: "patch",
        confirm_label:  "Approve application",
        success:        true,
        hidden_fields:  { status: "approved" }
      )
    end

    def reject_modal
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:          "Reject application",
        body:           "Reject the application for #{application.legal_name}? This action cannot be undone.",
        confirm_path:   merchant_path(application),
        confirm_method: "patch",
        confirm_label:  "Reject application",
        danger:         true,
        hidden_fields:  { status: "rejected" }
      )
    end

    def suspend_modal
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:          "Suspend merchant",
        body:           "#{application.legal_name} will immediately lose access to process payments.",
        confirm_path:   merchant_path(application),
        confirm_method: "patch",
        confirm_label:  "Suspend merchant",
        danger:         true,
        hidden_fields:  { status: "suspended" }
      )
    end

    def reactivate_modal
      authorize :merchants, :update?
      application = find_owned!(PortalMerchantApplication)
      render UI::ConfirmModal.new(
        title:          "Reactivate merchant",
        body:           "#{application.legal_name} will be able to process payments again.",
        confirm_path:   merchant_path(application),
        confirm_method: "patch",
        confirm_label:  "Reactivate merchant",
        success:        true,
        hidden_fields:  { status: "active" }
      )
    end

    private

    def resolve_user_display(user_code)
      return nil if user_code.blank?
      User.find_by(user_code: user_code)&.full_name || user_code
    end

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
