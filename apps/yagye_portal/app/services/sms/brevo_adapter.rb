# frozen_string_literal: true

module Sms
  # Brevo Transactional SMS adapter.
  # Docs: https://developers.brevo.com/reference/sendtransacsms
  #
  # To swap providers: implement a new adapter with .send_sms(to:, content:, tag:)
  # returning an Sms::Result, then set Rails.application.config.sms_adapter in
  # config/initializers/sms.rb.
  class BrevoAdapter
    ENDPOINT    = "https://api.brevo.com/v3/transactionalSMS/send"
    SENDER_NAME = "Yagye"
    MAX_CONTENT = 160

    Result = Data.define(:success, :message_id, :error)

    def self.send_sms(to:, content:, tag: nil)
      new(to:, content:, tag:).send
    end

    def initialize(to:, content:, tag: nil)
      @to      = normalize_number(to)
      @content = content.to_s.strip
      @tag     = tag
    end

    def send
      api_key = ENV["BREVO_API_KEY"]
      unless api_key.present?
        Rails.logger.error("[Sms::BrevoAdapter] BREVO_API_KEY not set")
        return Result.new(success: false, message_id: nil, error: "BREVO_API_KEY not configured")
      end

      conn = Faraday.new(url: ENDPOINT) do |f|
        f.request  :json
        f.response :json
        f.request  :retry, max: 2, interval: 0.5, retry_statuses: [ 429, 503 ]
        f.adapter  Faraday.default_adapter
      end

      Rails.logger.info("[Sms::BrevoAdapter] Sending SMS to #{masked_number} tag=#{@tag}")

      response = conn.post do |req|
        req.headers["api-key"]      = api_key
        req.headers["accept"]       = "application/json"
        req.headers["content-type"] = "application/json"
        req.body = build_payload
      end

      if response.status == 201
        mid = response.body["messageId"].to_s
        Rails.logger.info("[Sms::BrevoAdapter] SMS sent messageId=#{mid}")
        Result.new(success: true, message_id: mid, error: nil)
      else
        err = response.body["message"] || response.body.to_s
        Rails.logger.error("[Sms::BrevoAdapter] Failed status=#{response.status} error=#{err}")
        Result.new(success: false, message_id: nil, error: err)
      end
    rescue Faraday::Error => e
      Rails.logger.error("[Sms::BrevoAdapter] Network error: #{e.class} #{e.message}")
      Result.new(success: false, message_id: nil, error: e.message)
    end

    private

    def build_payload
      payload = {
        sender:    SENDER_NAME,
        recipient: @to,
        content:   @content,
        type:      "transactional"
      }
      payload[:tag] = @tag if @tag.present?
      payload
    end

    def normalize_number(number)
      number.to_s.gsub(/\D/, "")
    end

    def masked_number
      n = @to.to_s
      n.length > 6 ? "#{n[0..2]}****#{n[-3..]}" : "***"
    end
  end
end
