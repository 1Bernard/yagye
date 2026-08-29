# frozen_string_literal: true

module Payments
  class DisputesController < ApplicationController
    def index
      authorize :disputes, :index?
      tab = params[:tab].presence_in(%w[all open won lost]) || "all"
      render Disputes::IndexView.new(
        tab: tab, disputes: [], pagy: nil,
        query: params[:q], reason: params[:reason],
        date_from: params[:from], date_to: params[:to]
      )
    end

    def show
      authorize :disputes, :show?
    end
  end
end
