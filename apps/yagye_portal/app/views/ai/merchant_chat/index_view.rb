# frozen_string_literal: true

module Ai
  module MerchantChat
    class IndexView < ApplicationComponent
      include UI::Theme

      SUGGESTIONS = [
        "How much have I processed this month?",
        "Show me failed payments today",
        "What's my current payout balance?",
        "When's my next settlement?",
        "What's my success rate this week?"
      ].freeze

      def view_template
        turbo_frame_tag "drawer-frame",
          class: "flex flex-col h-full",
          data:  { controller: "ops-chat",
                   ops_chat_chat_url_value: ai_merchant_chat_path } do
          render UI::Drawer::Header.new(
            title:    "AI Assistant",
            subtitle: "Ask about your payments, settlements, and balances.",
            category: "ASSISTANT",
            icon:     :chart,
            palette:  "brand"
          )
          messages_area
          input_area
        end
      end

      private

      def messages_area
        div(class: "flex-1 overflow-y-auto px-5 py-5",
            data: { ops_chat_target: "messages" }) do
          render_assistant_bubble("Hello! I can help you understand your payment activity, check balances, and review your settlements. What would you like to know?")
          suggestion_chips
        end
      end

      def suggestion_chips
        div(class: "flex flex-wrap gap-2 mt-4 pl-10") do
          SUGGESTIONS.each do |s|
            button(type: "button",
                   class: "text-[12px] font-medium px-3 py-[6px] rounded-[9px] border border-gray-200 " \
                          "text-gray-500 bg-white hover:border-gray-400 hover:text-gray-800 transition-colors",
                   data: { action: "click->ops-chat#suggest",
                           ops_chat_text_param: s }) do
              plain s
            end
          end
        end
      end

      def input_area
        div(class: "flex-shrink-0 px-5 py-4 border-t border-gray-100 bg-gray-50") do
          form(data: { action: "submit->ops-chat#send",
                       ops_chat_target: "form",
                       turbo: false }) do
            div(class: "flex items-end gap-3") do
              textarea(name: "message",
                       rows: 1,
                       placeholder: "Ask about your payments, settlements, or balances…",
                       class: "#{TEXTAREA_FIELD} max-h-32",
                       data: { ops_chat_target: "input",
                               action: "keydown->ops-chat#keydown" })
              button(type: "submit",
                     class: "#{BTN_PRIMARY} flex-shrink-0",
                     style: "height:42px;padding:0 16px",
                     data: { ops_chat_target: "submit" }) do
                render UI::Icon.new(:paper_plane, class: ICON_SM)
                plain "Send"
              end
            end
          end
        end
      end

      def render_assistant_bubble(text)
        div(class: "flex items-start gap-3 mb-4") do
          div(class: "w-7 h-7 rounded-lg icon-brand flex items-center justify-center flex-shrink-0 mt-0.5") do
            span(class: "flex w-[13px] h-[13px]") do
              render UI::Icon.new(:chart, class: "w-full h-full")
            end
          end
          div(class: "flex-1 max-w-[85%] px-4 py-3 rounded-2xl rounded-tl-sm #{TYPE_BODY} leading-relaxed",
              style: "background: var(--surface)") do
            plain text
          end
        end
      end
    end
  end
end
