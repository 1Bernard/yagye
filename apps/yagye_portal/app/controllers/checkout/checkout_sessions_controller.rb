# frozen_string_literal: true

module Checkout
  class CheckoutSessionsController < ApplicationController
    def index
      authorize :checkout_session, :index?
      tab   = params[:tab].presence_in(%w[all open processing completed expired]) || "all"
      state = tab == "all" ? nil : tab

      stats_result = core.get_checkout_session_stats(current_user.merchant_code)
      stats = if stats_result.success?
        body = stats_result.body
        {
          total:     body["total"].to_i,
          completed: body["completed"].to_i,
          expired:   body["expired"].to_i
        }
      else
        { total: 0, completed: 0, expired: 0 }
      end

      result = core.list_checkout_sessions(
        merchant_code:   current_user.merchant_code,
        state:           state,
        payment_link_id: params[:payment_link_id].presence,
        limit:           100
      )
      all_sessions = result.success? ? (result.body["data"] || []) : []
      all_sessions = filter_sessions(all_sessions)

      pagy, sessions = pagy(all_sessions, limit: 25)
      render Checkout::CheckoutSessions::IndexView.new(
        sessions: sessions,
        pagy:     pagy,
        stats:    stats,
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
