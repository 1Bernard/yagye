# frozen_string_literal: true

module Account
  class HelpController < ApplicationController
    def index
      authorize :help, :index?
      render Help::IndexPage.new
    end
  end
end
