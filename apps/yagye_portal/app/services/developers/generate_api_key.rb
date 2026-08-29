# frozen_string_literal: true

module Developers
  # P13 stub — ApiKey model is built as part of the Developers integration
  # phase. This service object is the integration point; swap the stub
  # for real logic once the model and migration land.
  class GenerateApiKey
    Result = Struct.new(:success?, :api_key, :plain_key, :error, keyword_init: true)

    def initialize(name:, environment:, merchant_code:, created_by:)
      @name          = name
      @environment   = environment
      @merchant_code = merchant_code
      @created_by    = created_by
    end

    def call
      Result.new(success?: false, error: "API key management not yet available in this release")
    end
  end
end
