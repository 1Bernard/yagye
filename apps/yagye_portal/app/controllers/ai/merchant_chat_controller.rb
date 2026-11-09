# frozen_string_literal: true

module Ai
  class MerchantChatController < ApplicationController
    before_action :authenticate_user!
    before_action :require_merchant!

    SYSTEM_PROMPT = <<~PROMPT
      You are an AI analytics assistant for %<merchant_name>s's Yagye payment dashboard.
      Today's date: %<date>s

      Your job is to help merchants understand their payment data, settlements, and balances
      using the tools available to you. You are a data analyst, not a support bot or documentation service.

      Rules:
      - Use the available tools to get real data before answering. Never guess numbers.
      - If a tool returns no data or an error, say so clearly.
      - Format amounts in GHS (Ghana Cedis). Format rates as percentages.
      - Only answer questions about this merchant's own payments and payouts.
      - Never discuss other merchants or platform-level aggregate data.
      - If asked about API integration, webhooks, SDK setup, fees, or how the portal works,
        do not attempt to answer — instead say: "For that, check the Developer docs in your
        portal sidebar, or contact Yagye support." Keep this redirect brief and do not elaborate.
      - If asked to perform actions (revoke a key, add a team member, change settings),
        decline and direct the merchant to the relevant portal page.
    PROMPT

    def index
      skip_authorization
      render Ai::MerchantChat::IndexView.new
    end

    def create
      skip_authorization
      messages = sanitized_history
      return render json: { error: "Message is required" }, status: :unprocessable_entity if messages.empty?

      merchant_code = current_user.merchant_code
      dispatcher = Ai::MerchantToolDispatcher.new(merchant_code: merchant_code)
      client     = Ai::AnthropicClient.new

      result = client.chat(
        system:   format(SYSTEM_PROMPT, merchant_name: current_user.active_membership&.merchant_name.presence || merchant_code, date: Date.current.iso8601),
        messages: messages,
        tools:    dispatcher.tool_definitions,
        on_tool:  ->(name, input) { dispatcher.dispatch(name, input) }
      )

      if result.success?
        render json: { reply: result.text }
      else
        Rails.logger.warn("[Ai::MerchantChatController] #{result.error}")
        render json: { error: "AI assistant unavailable. Please try again." }, status: :service_unavailable
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::MerchantChatController] #{e.class}: #{e.message}")
      render json: { error: "An error occurred." }, status: :internal_server_error
    end

    private

    def sanitized_history
      raw = params[:history]
      return [] unless raw.is_a?(Array)
      raw.last(20).filter_map do |turn|
        role    = turn[:role].to_s
        content = turn[:content].to_s.strip
        next unless %w[user assistant].include?(role) && content.present?
        { role: role, content: content.truncate(4000) }
      end
    end

    def require_merchant!
      unless current_user&.merchant_user?
        render json: { error: "Not authorized" }, status: :forbidden
      end
    end
  end
end
