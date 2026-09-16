# frozen_string_literal: true

module Payments
  class DisputesController < ApplicationController
    def index
      authorize :disputes, :index?
      tab   = params[:tab].presence_in(%w[all open won lost]) || "all"
      scope = policy_scope(Dispute)
      pagy, disputes = pagy(
        Payments::DisputesQuery.new(scope).call(
          tab: tab, query: params[:q], reason: params[:reason],
          date_from: params[:from], date_to: params[:to]
        ),
        limit: 25
      )
      render Disputes::IndexView.new(
        tab: tab, disputes: disputes, pagy: pagy,
        query: params[:q], reason: params[:reason],
        date_from: params[:from], date_to: params[:to],
        stats: dispute_stats(scope)
      )
    end

    def show
      authorize :disputes, :show?
      dispute = decode_id(Dispute)
      render Disputes::ShowView.new(dispute: dispute)
    end
    private

    def dispute_stats(scope)
      today = Date.current.to_s
      {
        open:         scope.open.count,
        won:          scope.won.count,
        lost:         scope.lost.count,
        sla_breached: scope.open.where("network_deadline < ?", today).count
      }
    end
  end
end
