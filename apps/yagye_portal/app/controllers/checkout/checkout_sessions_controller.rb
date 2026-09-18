# frozen_string_literal: true

module Checkout
  class CheckoutSessionsController < ApplicationController
    def index
      authorize :checkout_session, :index?
      tab   = params[:tab].presence_in(%w[all open processing completed expired]) || "all"
      state = tab == "all" ? nil : tab
      result = core.list_checkout_sessions(
        merchant_code:   current_user.merchant_code,
        state:           state,
        payment_link_id: params[:payment_link_id].presence
      )
      sessions = result.success? ? (result.body["data"] || []) : []
      sessions = filter_sessions(sessions)
      render Checkout::CheckoutSessions::IndexView.new(
        sessions: sessions,
        query:    params[:q],
        tab:      tab
      )
    end

    def show
      authorize :checkout_session, :show?
      result = core.get_checkout_session(params[:id])
      return redirect_to checkout_sessions_path, alert: "Session not found." unless result.success?
      render Checkout::CheckoutSessions::ShowView.new(session: result.body)
    end

    private

    def filter_sessions(sessions)
      return sessions if params[:q].blank?
      q = params[:q].downcase
      sessions.select do |s|
        s["id"].to_s.downcase.include?(q) ||
          s["merchant_reference"].to_s.downcase.include?(q) ||
          s["description"].to_s.downcase.include?(q)
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
