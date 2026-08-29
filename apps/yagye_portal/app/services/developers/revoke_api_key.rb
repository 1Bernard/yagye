# frozen_string_literal: true

module Developers
  class RevokeApiKey
    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(api_key:, revoked_by:)
      @api_key    = api_key
      @revoked_by = revoked_by
    end

    def call
      Result.new(success?: false, error: "API key management not yet available in this release")
    end
  end
end
