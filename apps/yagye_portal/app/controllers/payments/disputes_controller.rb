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
        date_from: params[:from], date_to: params[:to]
      )
    end

    def show
      authorize :disputes, :show?
      dispute = policy_scope(Dispute).find(params[:id])
      render Disputes::ShowView.new(dispute: dispute)
    end
  end
end
