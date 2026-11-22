# frozen_string_literal: true

module Ai
  module MerchantChat
    class IndexView < ApplicationComponent
      include UI::Theme

      SUGGESTIONS = [
        { icon: :chart,         label: "Payment volume",        desc: "This month's totals and trends",         bg: "rgba(99,102,241,0.08)",  color: "#6366f1" },
        { icon: :trending_down, label: "Failed payments",       desc: "What failed today and why",              bg: "rgba(239,68,68,0.08)",   color: "#ef4444" },
        { icon: :wallet,        label: "Payout balance",        desc: "Current balance ready for settlement",   bg: "rgba(16,185,129,0.08)",  color: "#10b981" },
        { icon: :calendar,      label: "Next settlement",       desc: "When your next payout is due",           bg: "rgba(139,92,246,0.08)",  color: "#8b5cf6" },
        { icon: :bar_chart,     label: "Success rate",          desc: "This week's payment success metrics",    bg: "rgba(59,130,246,0.08)",  color: "#3b82f6" },
        { icon: :swap,          label: "Payment method split",  desc: "MoMo vs card vs other breakdown",        bg: "rgba(245,158,11,0.08)",  color: "#f59e0b" }
      ].freeze

      def view_template
        render Layout::Shell.new(active_nav: :ai_chat, title: "AI Assistant",
                                 padded: false, hide_sidebar: true,
                                 hide_topbar: true, show_kyb_banner: false) do
          full_page
        end
      end

      private

      def full_page
        div(class: "flex h-full overflow-hidden",
            data: { controller: "ai-page",
                    ai_page_chat_url_value: ai_merchant_chat_path,
                    ai_page_avatar_url_value: asset_path("chatbot.jpeg") }) do
          thread_sidebar
          main_area
        end
      end

      def thread_sidebar
        div(class: "w-[220px] flex-shrink-0 flex flex-col h-full",
            style: "background:#fff;border-right:1px solid #f0f0f0") do
          sidebar_header
          sidebar_new_chat_btn
          sidebar_search
          sidebar_section_label("Recent")
          sidebar_thread_list
        end
      end

      def sidebar_search
        div(class: "px-3 pb-2") do
          div(class: "flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg",
              style: "background:#f9fafb;border:1px solid #f0f0f0") do
            span(class: "flex-shrink-0 flex w-[11px] h-[11px]",
                 style: "color:#d1d5db") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "text",
                  placeholder: "Search…",
                  class: "flex-1 bg-transparent border-0 outline-none text-[12px] " \
                         "text-gray-700 placeholder-gray-400",
                  data: { ai_page_target: "searchInput",
                          action: "input->ai-page#filterThreads" })
          end
        end
      end

      def sidebar_header
        div(class: "flex items-center justify-between px-3 py-2.5",
            style: "border-bottom:1px solid #f5f5f5") do
          a(href: authenticated_root_path,
            class: "w-7 h-7 flex items-center justify-center rounded-lg transition-colors hover:bg-gray-100",
            style: "color:#9ca3af",
            title: "Back to dashboard") do
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:arrow_left, class: "w-full h-full") }
          end
          img(src: asset_path("yagye.png"), alt: "Yagye",
              style: "height:16px;width:auto;object-fit:contain;opacity:0.7")
          div(class: "w-6 h-6 rounded-lg flex items-center justify-center text-[10px] font-bold",
              style: "background:rgba(61,71,245,0.1);color:#3D47F5") do
            plain user_initials
          end
        end
      end

      def sidebar_new_chat_btn
        div(class: "px-3 pt-3 pb-2") do
          button(type: "button",
                 class: "flex items-center justify-center gap-2 w-full px-4 py-2.5 rounded-xl " \
                        "text-[12.5px] font-medium transition-colors " \
                        "hover:bg-gray-100 active:bg-gray-200",
                 style: "background:#f3f4f6;color:#374151;border:1px solid #ebebeb",
                 data: { action: "click->ai-page#newChat" }) do
            span(class: "flex w-[11px] h-[11px]", style: "color:#6b7280") do
              render UI::Icon.new(:plus, class: "w-full h-full")
            end
            plain "New conversation"
          end
        end
      end

      def sidebar_section_label(text)
        div(class: "px-4 pt-1 pb-1.5") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.08em]",
            style: "color:#c4c9d4") { plain text }
        end
      end

      def sidebar_thread_list
        div(class: "flex-1 overflow-y-auto px-2 pb-3",
            data: { ai_page_target: "threadsList" }) do
          3.times do
            div(class: "mx-1 my-1.5 h-[42px] rounded-xl animate-pulse",
                style: "background:#f3f4f6")
          end
        end
      end

      def main_area
        div(class: "flex-1 flex flex-col min-w-0 overflow-hidden",
            style: "background:#f9fafb") do
          div(class: "flex-1 overflow-y-auto pt-6",
              data: { ai_page_target: "messages" }) do
            welcome_section
          end
          input_bar
        end
      end

      def welcome_section
        div(class: "flex flex-col items-center justify-center min-h-full px-6 pb-24 pt-12 text-center",
            data: { ai_page_target: "welcome" }) do
          # Logo with glow ring
          div(class: "relative mx-auto mb-8",
              style: "width:72px;height:72px") do
            div(style: "position:absolute;inset:-20px;background:radial-gradient(circle," \
                       "rgba(61,71,245,0.12) 0%,transparent 70%);border-radius:50%;pointer-events:none")
            div(class: "w-full h-full rounded-2xl flex items-center justify-center",
                style: "background:#fff;box-shadow:0 2px 16px rgba(61,71,245,0.12)," \
                       "0 1px 4px rgba(0,0,0,0.06);border:1px solid rgba(61,71,245,0.08)") do
              img(src: asset_path("yagye.png"), alt: "Yagye",
                  style: "width:36px;height:36px;object-fit:contain")
            end
          end

          p(class: "text-[14px] font-medium mb-1.5",
            style: "color:#9ca3af") { plain "Hi #{current_user_first_name}," }
          p(class: "text-[28px] font-bold mb-2",
            style: "color:#0f172a;letter-spacing:-0.03em;line-height:1.1") { plain "How can I help?" }
          p(class: "text-[13.5px] mb-10 max-w-[340px] leading-relaxed",
            style: "color:#a3aab8") do
            plain "Ask about payments, balances, settlements, or anything else."
          end

          div(class: "grid grid-cols-2 md:grid-cols-3 gap-2.5 max-w-[640px] w-full text-left") do
            SUGGESTIONS.each do |s|
              button(type: "button",
                     class: "group flex flex-col px-4 py-4 rounded-2xl transition-all text-left " \
                            "bg-white border border-gray-100/80 " \
                            "hover:border-gray-200 hover:shadow-md hover:-translate-y-0.5 " \
                            "active:translate-y-0 active:shadow-sm",
                     style: "box-shadow:0 1px 3px rgba(0,0,0,0.04)",
                     data: { action: "click->ai-page#suggest",
                             ai_page_text_param: s[:label] }) do
                div(class: "w-8 h-8 rounded-xl flex items-center justify-center mb-3",
                    style: "background:#{s[:bg]}") do
                  span(class: "flex w-[14px] h-[14px]",
                       style: "color:#{s[:color]}") do
                    render UI::Icon.new(s[:icon], class: "w-full h-full")
                  end
                end
                p(class: "text-[13px] font-semibold mb-0.5 leading-tight",
                  style: "color:#0f172a") { plain s[:label] }
                p(class: "text-[11.5px] leading-snug",
                  style: "color:#9ca3af") { plain s[:desc] }
              end
            end
          end
        end
      end

      def input_bar
        div(class: "flex-shrink-0 px-6 py-5",
            style: "background:#f9fafb") do
          # CSV file chip
          div(class: "hidden mb-3 flex justify-center",
              data: { ai_page_target: "fileChip" }) do
            div(class: "flex items-center gap-2 px-3 py-1.5 rounded-[10px] w-fit",
                style: "background:#f1f5f9;border:1px solid #e2e8f0") do
              span(class: "flex-shrink-0 flex w-[11px] h-[11px]",
                   style: "color:#94a3b8") { render UI::Icon.new(:file, class: "w-full h-full") }
              span(class: "text-[11.5px] font-medium max-w-[220px] truncate",
                   style: "color:#475569",
                   data: { ai_page_target: "fileLabel" }) { }
              button(type: "button",
                     class: "flex-shrink-0 flex w-[11px] h-[11px] ml-1.5 hover:opacity-70 transition-opacity",
                     style: "color:#94a3b8",
                     data: { action: "click->ai-page#removeFile" }) do
                render UI::Icon.new(:x, class: "w-full h-full")
              end
            end
          end

          form(data: { action: "submit->ai-page#send",
                       ai_page_target: "form",
                       turbo: false }) do
            div(class: "max-w-[720px] mx-auto rounded-2xl overflow-hidden transition-all",
                style: "background:#fff;" \
                       "border:1.5px solid #e8eaed;" \
                       "box-shadow:0 4px 20px rgba(0,0,0,0.06),0 1px 4px rgba(0,0,0,0.04)") do
              div(class: "flex items-end px-4 py-3 gap-3") do
                textarea(name: "message",
                         rows: 1,
                         placeholder: "Ask about your payments, settlements, or balances…",
                         class: "flex-1 resize-none border-0 bg-transparent text-[14px] " \
                                "text-gray-800 leading-relaxed placeholder-gray-400 outline-none " \
                                "max-h-[140px] py-0.5",
                         data: { ai_page_target: "input",
                                 action: "keydown->ai-page#keydown input->ai-page#autoResizeInput" })
                div(class: "flex items-center gap-1.5 flex-shrink-0 pb-0.5") do
                  button(type: "button",
                         class: "w-8 h-8 rounded-xl flex items-center justify-center " \
                                "transition-colors hover:bg-gray-100",
                         style: "color:#9ca3af",
                         title: "Attach CSV",
                         data: { action: "click->ai-page#attach" }) do
                    span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:file, class: "w-full h-full") }
                  end
                  button(type: "submit",
                         class: "h-8 w-8 rounded-xl flex items-center justify-center " \
                                "text-white transition-all " \
                                "disabled:opacity-30 disabled:cursor-not-allowed hover:opacity-90 active:scale-95",
                         style: "background:#3D47F5",
                         data: { ai_page_target: "submit" }) do
                    span(class: "flex w-[14px] h-[14px]") do
                      render UI::Icon.new(:paper_plane, class: "w-full h-full")
                    end
                  end
                end
              end
            end

            input(type: "file", accept: ".csv,text/csv",
                  class: "hidden",
                  data: { ai_page_target: "fileInput",
                          action: "change->ai-page#fileChange" })
          end
        end
      end

      def current_user_first_name
        current_user&.full_name.to_s.split.first.presence || "there"
      end

      def user_initials
        current_user&.full_name.to_s.split.map { |w| w[0] }.first(2).join.upcase.presence || "?"
      end
    end
  end
end
