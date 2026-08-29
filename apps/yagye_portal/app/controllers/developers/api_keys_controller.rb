# frozen_string_literal: true

module Developers
  class ApiKeysController < ApplicationController
    def index
      authorize :developers, :index?
      @tab = params[:tab].presence_in(%w[api_keys webhooks logs]) || "api_keys"
      @env = params[:env].presence_in(%w[sandbox live]) || "sandbox"
    end
  end
end
