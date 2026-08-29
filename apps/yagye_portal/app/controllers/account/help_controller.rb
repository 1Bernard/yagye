# frozen_string_literal: true

module Account
  class HelpController < ApplicationController
    def index
      authorize :help, :index?
    end
  end
end
