# frozen_string_literal: true

module Layout
  class AiChatPanel < ApplicationComponent
    include UI::Theme

    OPS_SUGGESTIONS = [
      { icon: :chart,         label: "Payment volume this month"  },
      { icon: :bar_chart,     label: "Provider health check"      },
      { icon: :trending_down, label: "Failed payments today"      },
      { icon: :swap,          label: "MoMo vs card split"         },
      { icon: :bank,          label: "Stuck settlements"          },
      { icon: :filter,        label: "Risk flag summary"          }
    ].freeze

    MERCHANT_SUGGESTIONS = [
      { icon: :chart,         label: "Volume this month"          },
      { icon: :trending_down, label: "Failed payments today"      },
      { icon: :wallet,        label: "Current payout balance"     },
      { icon: :calendar,      label: "Next settlement date"       },
      { icon: :bar_chart,     label: "Success rate this week"     },
      { icon: :swap,          label: "Payment method split"       }
    ].freeze

    def initialize(user:)
      @user = user
    end

    def view_template
      is_ops      = @user.internal_staff?
      chat_url    = is_ops ? "/ai/ops-chat" : "/ai/chat"
      first_name  = @user.full_name.to_s.split.first.presence || "there"
      greeting    = is_ops \
        ? "Analyze payments, check provider health, review risk flags, and more." \
        : "Check balances, review payments, and understand your activity."
      suggestions = is_ops ? OPS_SUGGESTIONS : MERCHANT_SUGGESTIONS
      placeholder = "Ask me anything…"

      div(data: { controller: "ai-chat",
                  ai_chat_chat_url_value: chat_url,
                  action: "ai:toggle@window->ai-chat#toggle keydown.esc@window->ai-chat#close" }) do
        # Backdrop
        div(class: "fixed inset-0 z-[60] opacity-0 pointer-events-none transition-opacity duration-300",
            style: "background:rgba(0,0,0,0.25);backdrop-filter:blur(2px)",
            data: { ai_chat_target: "overlay",
                    action: "click->ai-chat#close" })

        # Panel
        div(class: "fixed top-0 right-0 bottom-0 w-full sm:w-[400px] z-[70] flex flex-col " \
                   "translate-x-full transition-transform duration-300 ease-out bg-white overflow-hidden",
            style: "border-left:1px solid #f0f0f0;box-shadow:-12px 0 48px rgba(0,0,0,0.07)",
            data: { ai_chat_target: "panel" }) do
          header_section   # starts hidden; revealed on first send
          messages_section(first_name, greeting, suggestions)
          input_section(placeholder)
        end
      end
    end

    private

    # ── Header ────────────────────────────────────────────────────────────────

    def header_section
      div(class: "flex-shrink-0 flex items-center justify-between px-4 py-3",
          style: "border-bottom:1px solid #f5f5f5") do
        img(src: asset_path("yagye.png"),
            alt: "Yagye",
            class: "invisible",
            style: "height:26px;width:auto;object-fit:contain;transition:opacity 0.25s ease",
            data: { ai_chat_target: "header" })
        button(type: "button",
               class: "w-8 h-8 rounded-lg flex items-center justify-center transition-colors hover:bg-gray-100",
               style: "color:#adb5bd",
               data: { action: "click->ai-chat#close" }) do
          span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:x, class: "w-full h-full") }
        end
      end
    end

    # ── Messages ──────────────────────────────────────────────────────────────

    def messages_section(first_name, greeting, suggestions)
      div(class: "flex-1 overflow-y-auto pt-4",
          style: "scroll-behavior:smooth",
          data: { ai_chat_target: "messages" }) do
        # Welcome / empty state — hidden once the user sends a message
        div(class: "flex flex-col items-center px-6 pt-10 pb-6 text-center",
            data: { ai_chat_target: "welcome" }) do
          # Logo mark — minimal, centered
          img(src: asset_path("yagye.png"),
              alt: "Yagye",
              class: "mx-auto mb-5",
              style: "width:48px;height:48px;object-fit:contain;" \
                     "filter:drop-shadow(0 3px 10px rgba(99,102,241,0.18))")

          p(class: "text-[14px] mb-0.5",
            style: "color:#adb5bd;font-weight:500") { plain "Hi #{first_name}," }
          p(class: "font-bold leading-tight mb-3",
            style: "font-size:20px;color:#0f172a;letter-spacing:-0.025em") { plain "How can I help?" }
          p(class: "text-[12.5px] leading-relaxed max-w-[260px]",
            style: "color:#adb5bd") { plain greeting }

          # 2-column suggestion chip grid
          div(class: "mt-7 grid grid-cols-2 gap-2 w-full text-left") do
            suggestions.each do |s|
              button(type: "button",
                     class: "ai-suggestion-chip flex items-center gap-2 px-3 py-2.5 rounded-xl transition-all",
                     style: "border:1px solid #ebebeb;background:#fafafa;color:#374151",
                     data: { action: "click->ai-chat#suggest",
                             ai_chat_text_param: s[:label] }) do
                span(class: "flex-shrink-0 flex w-[13px] h-[13px]",
                     style: "color:#6366f1") { render UI::Icon.new(s[:icon], class: "w-full h-full") }
                span(class: "text-[12px] font-medium leading-tight") { plain s[:label] }
              end
            end
          end
        end
      end
    end

    # ── Input ─────────────────────────────────────────────────────────────────

    def input_section(placeholder)
      div(class: "flex-shrink-0 px-4 pb-5 pt-3",
          style: "border-top:1px solid #f5f5f5;background:#fff") do
        # CSV file chip — hidden until a file is chosen
        div(class: "hidden mb-2",
            data: { ai_chat_target: "fileChip" }) do
          div(class: "flex items-center gap-2 px-3 py-1.5 rounded-[10px] w-fit",
              style: "background:#f8fafc;border:1px solid #e2e8f0") do
            span(class: "flex-shrink-0 flex w-[11px] h-[11px]",
                 style: "color:#94a3b8") { render UI::Icon.new(:file, class: "w-full h-full") }
            span(class: "text-[11.5px] font-medium max-w-[220px] truncate",
                 style: "color:#475569",
                 data: { ai_chat_target: "fileLabel" }) {}
            button(type: "button",
                   class: "flex-shrink-0 flex w-[11px] h-[11px] ml-1",
                   style: "color:#cbd5e1",
                   data: { action: "click->ai-chat#removeFile" }) do
              render UI::Icon.new(:x, class: "w-full h-full")
            end
          end
        end

        form(data: { action: "submit->ai-chat#send",
                     ai_chat_target: "form",
                     turbo: false }) do
          div(class: "ai-input-wrap flex items-center gap-1.5 pl-3.5 pr-2 rounded-[14px] transition-all",
              style: "border:1.5px solid #ebebeb;background:#fafafa;min-height:46px") do
            span(class: "flex-shrink-0 flex w-[13px] h-[13px]",
                 style: "color:#d1d5db") { render UI::Icon.new(:search, class: "w-full h-full") }
            textarea(name: "message",
                     rows: 1,
                     placeholder: placeholder,
                     class: "flex-1 resize-none border-0 bg-transparent py-3 text-[13.5px] text-gray-800 " \
                            "leading-relaxed placeholder-gray-400 outline-none max-h-[120px]",
                     data: { ai_chat_target: "input",
                             action: "keydown->ai-chat#keydown input->ai-chat#autoResizeInput" })
            # Attach CSV — icon-only, inside pill
            button(type: "button",
                   class: "flex-shrink-0 w-7 h-7 rounded-lg flex items-center justify-center transition-colors hover:bg-gray-100",
                   style: "color:#cbd5e1",
                   title: "Attach CSV",
                   data: { action: "click->ai-chat#attach" }) do
              span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:file, class: "w-full h-full") }
            end
            # Send — dark, neutral
            button(type: "submit",
                   class: "flex-shrink-0 w-7 h-7 rounded-[9px] flex items-center justify-center transition-all " \
                          "disabled:opacity-25 disabled:cursor-not-allowed",
                   style: "background:#0f172a;color:#fff",
                   data: { ai_chat_target: "submit" }) do
              span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:paper_plane, class: "w-full h-full") }
            end
          end

          input(type: "file", accept: ".csv,text/csv",
                class: "hidden",
                data: { ai_chat_target: "fileInput",
                        action: "change->ai-chat#fileChange" })
        end
      end
    end
  end
end
