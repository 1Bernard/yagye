# frozen_string_literal: true

module Payments
  class ReservesController < ApplicationController
    def index
      authorize :reserve, :index?, policy_class: ReservePolicy
      render Payments::Reserves::IndexView.new
    end
  end
end
