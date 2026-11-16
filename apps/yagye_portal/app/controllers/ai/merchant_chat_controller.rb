# frozen_string_literal: true

module Ai
  class MerchantChatController < ApplicationController
    include Ai::ChatHistory

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

      raw = params[:message].to_s.strip.truncate(4000)
      return render json: { error: "Message is required" }, status: :unprocessable_entity if raw.blank?

      thread = find_or_create_thread(params[:thread_id])
      thread.ai_chat_messages.create!(role: "user", content: raw)

      merchant_code = current_user.merchant_code
      dispatcher    = Ai::MerchantToolDispatcher.new(merchant_code: merchant_code)
      client        = Ai::AnthropicClient.new

      result = client.chat(
        system:   format(SYSTEM_PROMPT,
                         merchant_name: current_user.active_membership&.merchant_name.presence || merchant_code,
                         date:          Date.current.iso8601),
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
        Rails.logger.warn("[Ai::MerchantChatController] #{result.error}")
        render json: { error: "AI assistant unavailable. Please try again." }, status: :service_unavailable
      end
    rescue StandardError => e
      Rails.logger.error("[Ai::MerchantChatController] #{e.class}: #{e.message}")
      render json: { error: "An error occurred." }, status: :internal_server_error
    end

    private

    def chat_context = AiChatThread::CONTEXT_MERCHANT

    def require_merchant!
      render json: { error: "Not authorized" }, status: :forbidden unless current_user&.merchant_user?
    end
  end
end
