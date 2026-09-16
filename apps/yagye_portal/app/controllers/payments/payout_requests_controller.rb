# frozen_string_literal: true

module Payments
  class PayoutRequestsController < ApplicationController
    def index
      authorize PortalPayoutRequest, :index?
      scope = policy_scope(PortalPayoutRequest)
      pagy, requests = pagy(scope.recent, limit: 25)
      render Payments::PayoutRequests::IndexView.new(requests: requests, pagy: pagy)
    end

    def new
      authorize PortalPayoutRequest, :new?
      unsettled = unsettled_balance(current_user.merchant_code)
      render Payments::PayoutRequests::NewView.new(
        unsettled_amount:   unsettled[:amount],
        unsettled_currency: unsettled[:currency]
      )
    end

    def create
      authorize PortalPayoutRequest, :create?

      req = PortalPayoutRequest.new(
        merchant_code: current_user.merchant_code,
        requested_by:  current_user.user_code,
        currency:      "GHS",
        reason:        params[:reason].to_s.strip,
        amount_cents:  parse_amount(params[:amount_cents])
      )

      if req.save
        redirect_to payouts_path,
                    notice: "Payout request submitted. Our team will review within 1 business day."
      else
        redirect_to new_payout_request_path,
                    alert:  req.errors.full_messages.first || "Could not submit request."
      end
    end

    def show
      req = PortalPayoutRequest.find(params[:id])
      authorize req
      render Payments::PayoutRequests::ShowView.new(request: req)
    end

    def approve
      req = PortalPayoutRequest.find(params[:id])
      authorize req, :review?
      req.update!(
        state:         "approved",
        reviewed_by:   current_user.user_code,
        reviewed_at:   Time.current,
        reviewer_note: params[:note].to_s.strip.presence
      )
      redirect_to payout_request_path(req), notice: "Request approved."
    end

    def reject
      req = PortalPayoutRequest.find(params[:id])
      authorize req, :review?
      req.update!(
        state:         "rejected",
        reviewed_by:   current_user.user_code,
        reviewed_at:   Time.current,
        reviewer_note: params[:note].to_s.strip.presence
      )
      redirect_to payout_request_path(req), notice: "Request rejected."
    end

    private

    def parse_amount(raw)
      return nil if raw.blank?
      cents = (raw.to_f * 100).round
      cents.positive? ? cents : nil
    end

    def unsettled_balance(merchant_code)
      scope = PortalSettlement.for_merchant(merchant_code)
                              .where(state: %w[pending processing awaiting_approval])
      total    = scope.sum(:expected_net)
      currency = scope.pick(:currency) || "GHS"
      { amount: total, currency: currency }
    end
  end
end
