# frozen_string_literal: true

module Payments
  class DisputesController < ApplicationController
    def index
      authorize :disputes, :index?
      @tab      = params[:tab].presence_in(%w[all open won lost]) || "all"
      @disputes = []
      @pagy     = nil
    end

    def show
      authorize :disputes, :show?
    end
  end
end
