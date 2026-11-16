# frozen_string_literal: true

module Ai
  class OpsChatController < ApplicationController
    include Ai::ChatHistory

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

      raw = params[:message].to_s.strip.truncate(4000)
      return render json: { error: "Message is required" }, status: :unprocessable_entity if raw.blank?

      thread = find_or_create_thread(params[:thread_id])
      thread.ai_chat_messages.create!(role: "user", content: raw)

      dispatcher = Ai::OpsToolDispatcher.new
      client     = Ai::AnthropicClient.new

      result = client.chat(
        system:   format(SYSTEM_PROMPT, date: Date.current.iso8601),
        messages: thread.messages_for_llm,
        tools:    dispatcher.tool_definitions,
        on_tool:  ->(name, input) { dispatcher.dispatch(name, input) }
      )

      if result.success?
        thread.ai_chat_messages.create!(role: "assistant", content: result.text)
        thread.update!(
          last_message_at: Time.current,
          title:           thread.title.presence || AiChatThread.title_from(raw)
        )
        render json: { reply: result.text, thread_id: thread.id }
      else
        Rails.logger.warn("[Ai::OpsChatController] #{result.error}")
        render json: { error: "AI assistant unavailable. Please try again." }, status: :service_unavailable
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::OpsChatController] #{e.class}: #{e.message}")
      render json: { error: "An error occurred." }, status: :internal_server_error
    end

    private

    def chat_context = AiChatThread::CONTEXT_OPS

    def require_ops!
      render json: { error: "Not authorized" }, status: :forbidden unless current_user&.internal_staff?
    end
  end
end
