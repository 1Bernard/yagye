# frozen_string_literal: true

module Ai
  class OpsChatController < ApplicationController
    before_action :authenticate_user!
    before_action :require_ops!

    SYSTEM_PROMPT = <<~PROMPT
      You are an AI analytics assistant for Yagye PSP (Payment Service Provider) operations team.
      Today's date: %<date>s

      You help the ops team understand payment metrics, provider health, risk flags, and settlements.

      Rules:
      - Use the available tools to get real data before answering. Never guess numbers.
      - If a tool returns no data or an error, say so clearly.
      - Format amounts in GHS (Ghana Cedis). Format rates as percentages.
      - Never discuss individual customer PII (names, MSISDNs, card numbers).
      - Keep answers concise and factual. If you don't know, say so.
      - Only answer questions about payments, providers, risk, and settlements.
    PROMPT

    def index
      skip_authorization
      render Ai::OpsChat::IndexView.new
    end

    def create
      skip_authorization
      messages = sanitized_history
      return render json: { error: "Message is required" }, status: :unprocessable_entity if messages.empty?

      dispatcher = Ai::OpsToolDispatcher.new
      client     = Ai::AnthropicClient.new

      result = client.chat(
        system:   format(SYSTEM_PROMPT, date: Date.current.iso8601),
        messages: messages,
        tools:    dispatcher.tool_definitions,
        on_tool:  ->(name, input) { dispatcher.dispatch(name, input) }
      )

      if result.success?
        render json: { reply: result.text }
      else
        Rails.logger.warn("[Ai::OpsChatController] #{result.error}")
        render json: { error: "AI assistant unavailable. Please try again." }, status: :service_unavailable
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::OpsChatController] #{e.class}: #{e.message}")
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

    def require_ops!
      unless current_user&.internal_staff?
        render json: { error: "Not authorized" }, status: :forbidden
      end
    end
  end
end
