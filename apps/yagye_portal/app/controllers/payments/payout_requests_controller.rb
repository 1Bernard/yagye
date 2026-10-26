# frozen_string_literal: true

module Payments
  class PayoutRequestsController < ApplicationController
    def index
      authorize PortalPayoutRequest, :index?
      scope = policy_scope(PortalPayoutRequest)
      pagy, requests = pagy(scope.recent, limit: 25)
      render Payments::PayoutRequests::IndexView.new(
        requests: requests,
        pagy:     pagy,
        stats:    {
          pending:  scope.pending_review.count,
          approved: scope.where(state: "approved").count,
          rejected: scope.where(state: "rejected").count
        }
      )
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
        amount:        parse_amount(params[:amount])
      )

      if req.save
        audit(action: "payout_request.submitted", resource_type: "payout_request",
              outcome: "succeeded", resource_code: req.id.to_s,
              metadata: { amount: req.amount, currency: req.currency })
        redirect_to payouts_path,
                    notice: "Payout request submitted. Our team will review within 1 business day."
      else
        audit(action: "payout_request.submitted", resource_type: "payout_request",
              outcome: "failed")
        redirect_to new_payout_request_path,
                    alert:  req.errors.full_messages.first || "Could not submit request."
      end
    end

    def show
      req = find_owned!(PortalPayoutRequest)
      authorize req
      render Payments::PayoutRequests::ShowView.new(request: req)
    end

    def approve
      req = find_owned!(PortalPayoutRequest)
      authorize req, :review?
      if req.requested_by == current_user.user_code
        return redirect_to payout_request_path(req),
                           alert: "You submitted this request and cannot also approve it (maker-checker)."
      end

      req.update!(
        state:         "approved",
        reviewed_by:   current_user.user_code,
        reviewed_at:   Time.current,
        reviewer_note: params[:note].to_s.strip.presence
      )
      audit(action: "payout_request.approved", resource_type: "payout_request",
            outcome: "succeeded", resource_code: req.id.to_s,
            metadata: { merchant_code: req.merchant_code, amount: req.amount })
      redirect_to payout_request_path(req), notice: "Request approved."
    end

    def reject
      req = find_owned!(PortalPayoutRequest)
      authorize req, :review?
      if req.requested_by == current_user.user_code
        return redirect_to payout_request_path(req),
                           alert: "You submitted this request and cannot also reject it (maker-checker)."
      end

      req.update!(
        state:         "rejected",
        reviewed_by:   current_user.user_code,
        reviewed_at:   Time.current,
        reviewer_note: params[:note].to_s.strip.presence
      )
      audit(action: "payout_request.rejected", resource_type: "payout_request",
            outcome: "succeeded", resource_code: req.id.to_s,
            reason: params[:note].to_s.strip.presence,
            metadata: { merchant_code: req.merchant_code })
      redirect_to payout_request_path(req), notice: "Request rejected."
    end

    private

    def parse_amount(raw)
      return nil if raw.blank?
      cents = (raw.to_f * 100).round
      cents.positive? ? cents : nil
    end

    def unsettled_balance(merchant_code)
      ::Payouts::PendingSettlementQuery.new(merchant_code).call.slice(:amount, :currency)
    end
  end
end
