# frozen_string_literal: true

module Payments
  class EscrowHoldsController < ApplicationController
    def index
      authorize :escrow_holds, :index?
      state  = params[:state].presence_in(%w[held disputed released refunded]) || nil
      result = core.list_escrow_holds(merchant_code: effective_merchant_code, state: state)
      holds  = result.success? ? Array(result.body["data"]) : []

      render Payments::EscrowHolds::IndexView.new(holds: holds, state_filter: state)
    end

    def show
      authorize :escrow_holds, :show?
      result = core.get_escrow_hold(params[:id])
      return redirect_to escrow_holds_path, alert: "Escrow hold not found." unless result.success?

      hold = result.body
      render Payments::EscrowHolds::ShowView.new(hold: hold)
    end

    def resolve_dispute
      authorize :escrow_holds, :resolve?
      outcome = params[:outcome].presence_in(%w[release refund]) || "release"
      note    = params[:note].to_s.strip

      result = core.resolve_escrow_dispute(params[:id], outcome: outcome, note: note.presence || "Resolved by ops.")
      if result.success?
        redirect_to escrow_hold_path(params[:id]), notice: "Dispute resolved — hold #{outcome == 'release' ? 'released to merchant' : 'refunded to buyer'}."
      else
        redirect_to escrow_hold_path(params[:id]), alert: result.error_message || "Could not resolve dispute."
      end
    end

    private

    def effective_merchant_code
      current_user.internal_staff? ? params[:merchant_code].to_s.presence : current_user.merchant_code
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
