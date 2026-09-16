# frozen_string_literal: true

module Account
  class KycController < ApplicationController
    def index
      authorize :kyc, :index?
      tier = current_user.merchant_tier || 1
      render Account::KycView.new(tier: tier)
    end
  end
end
