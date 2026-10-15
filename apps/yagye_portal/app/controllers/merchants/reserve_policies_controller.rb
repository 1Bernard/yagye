# frozen_string_literal: true

module Merchants
  class ReservePoliciesController < ApplicationController
    def new_modal
      authorize :reserve_policies, :manage?
      application = decode_id(PortalMerchantApplication)
      render Merchants::ReservePolicies::NewModalView.new(application: application)
    end

    def create
      authorize :reserve_policies, :manage?
      application = decode_id(PortalMerchantApplication)

      unless application.merchant_code.present?
        return redirect_to(merchant_path(application),
                           alert: "No merchant account linked — approve the application first.")
      end

      bps   = nil
      fixed = nil
      if params[:kind] == "rolling"
        bps = (params[:rate].to_f * 100).round
      elsif params[:kind] == "fixed"
        fixed = (params[:fixed_amount].to_f * 100).round
      end

      result = CoreApiClient.new.create_reserve_policy(
        application.merchant_code,
        kind:           params[:kind],
        percentage_bps: bps,
        fixed_amount:   fixed,
        currency:       application.default_currency.presence || "GHS",
        hold_days:      params[:hold_days].to_i,
        mode:           params[:mode].presence || "live",
        reason:         params[:reason].presence,
        created_by:     current_user.user_code
      )

      if result.success?
        AuditLog.record(
          actor:         current_user,
          action:        "reserve_policy.created",
          resource_type: "merchant",
          resource_code: application.merchant_code,
          outcome:       "succeeded"
        )
        redirect_to merchant_path(application),
                    notice: "Reserve policy created. A second ops manager must approve before funds are withheld."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end

    def approve_modal
      authorize :reserve_policies, :approve?
      application = decode_id(PortalMerchantApplication)
      policy_id   = params[:policy_id]

      if sod_violation?(application.merchant_code, policy_id)
        return render UI::ConfirmModal.new(
          title:         "Cannot approve",
          body:          "You created this reserve policy. A different ops officer must approve it (maker-checker).",
          confirm_path:  merchant_path(application),
          confirm_label: "OK",
          danger:        false
        )
      end

      render Merchants::ReservePolicies::ApproveModalView.new(
        application: application,
        policy_id:   policy_id
      )
    end

    def approve
      authorize :reserve_policies, :approve?
      application = decode_id(PortalMerchantApplication)
      policy_id   = params[:policy_id]

      if sod_violation?(application.merchant_code, policy_id)
        return redirect_to merchant_path(application),
                           alert: "You created this reserve policy and cannot approve it (maker-checker)."
      end

      result = CoreApiClient.new.approve_reserve_policy(
        policy_id,
        approved_by: current_user.user_code
      )

      if result.success?
        policy            = result.body
        auto_activates_at = begin
                              Time.parse(policy["auto_activates_at"].to_s)
                            rescue
                              Time.now + 7.days
                            end

        merchant_owner = User
          .joins(:merchant_memberships)
          .where(merchant_memberships: { merchant_code: application.merchant_code, state: "active" })
          .joins(:active_user_roles)
          .where(user_roles: { role_key: "merchant_owner" })
          .first

        if merchant_owner
          ReservePolicyMailer.merchant_notification(
            merchant_email:    merchant_owner.email,
            merchant_name:     application.legal_name,
            policy:            policy,
            auto_activates_at: auto_activates_at
          ).deliver_later
        end

        AuditLog.record(
          actor:         current_user,
          action:        "reserve_policy.approved",
          resource_type: "merchant",
          resource_code: application.merchant_code,
          outcome:       "succeeded"
        )
        redirect_to merchant_path(application),
                    notice: "Reserve policy approved. The merchant has been notified and must acknowledge within 7 days."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end

    private

    def sod_violation?(merchant_code, policy_id)
      result = CoreApiClient.new.get_reserves(merchant_code)
      return false unless result.success?

      reserves = result.body["reserves"] || [result.body["policy"]].compact
      policy   = reserves.find { |p| p.is_a?(Hash) && p["id"].to_s == policy_id.to_s }
      policy&.fetch("created_by", nil) == current_user.user_code
    end

    public

    def deactivate_modal
      authorize :reserve_policies, :manage?
      application = decode_id(PortalMerchantApplication)
      policy_id   = params[:policy_id]
      render Merchants::ReservePolicies::DeactivateModalView.new(
        application: application,
        policy_id:   policy_id
      )
    end

    def deactivate
      authorize :reserve_policies, :manage?
      application = decode_id(PortalMerchantApplication)
      policy_id   = params[:policy_id]

      result = CoreApiClient.new.deactivate_reserve_policy(policy_id)

      if result.success?
        AuditLog.record(
          actor:         current_user,
          action:        "reserve_policy.deactivated",
          resource_type: "merchant",
          resource_code: application.merchant_code,
          outcome:       "succeeded"
        )
        redirect_to merchant_path(application),
                    notice: "Reserve policy deactivated. No further funds will be withheld."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end
  end
end
