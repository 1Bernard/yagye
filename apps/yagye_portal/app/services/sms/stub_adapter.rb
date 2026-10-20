# frozen_string_literal: true

module Sms
  # No-op adapter for test and development — logs instead of sending.
  class StubAdapter
    Result = Data.define(:success, :message_id, :error)

    def self.send_sms(to:, content:, tag: nil)
      Rails.logger.info("[Sms::StubAdapter] STUB SMS to=#{to} tag=#{tag} content=#{content.truncate(60)}")
      Result.new(success: true, message_id: "stub-#{SecureRandom.hex(4)}", error: nil)
    end
  end
end
