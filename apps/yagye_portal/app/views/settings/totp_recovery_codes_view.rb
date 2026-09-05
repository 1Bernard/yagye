# frozen_string_literal: true

module Settings
  class TotpRecoveryCodesView < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, recovery_codes:)
      @current_user   = current_user
      @recovery_codes = recovery_codes
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :settings,
        title: "Save your recovery codes",
        breadcrumbs: [
          { label: "Settings", href: settings_path },
          { label: "Security", href: settings_path(tab: "security") },
          { label: "Recovery codes" }
        ]
      ) do
        div(class: "max-w-[560px]") do
          warning_banner
          codes_card
          done_action
        end
      end
    end

    private

    def warning_banner
      div(class: "flex items-start gap-4 rounded-2xl px-5 py-4 mb-6",
          style: "background:rgba(217,119,6,0.08);border:1px solid rgba(217,119,6,0.25)") do
        div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 mt-[1px]",
            style: "background:rgba(217,119,6,0.15)") do
          span(class: "flex w-[15px] h-[15px] text-amber-600") do
            render UI::Icon.new(:alert_triangle, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[13px] font-semibold text-gray-900 mb-[2px]") do
            plain "Save these codes now — you won't see them again."
          end
          p(class: TYPE_CAPTION) do
            plain "Each code can be used once to sign in if you lose access to your authenticator app. Store them in a password manager or a secure location."
          end
        end
      end
    end

    def codes_card
      div(class: "bg-white rounded-2xl border border-gray-100 overflow-hidden mb-5") do
        div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
          p(class: TYPE_TITLE) { plain "Recovery codes" }
          button(
            type: "button",
            class: "inline-flex items-center gap-[6px] px-3 py-[7px] rounded-lg border border-gray-200 " \
                   "text-[12px] font-medium text-gray-600 hover:bg-gray-50 transition-colors",
            data: { action: "click->clipboard#copy", clipboard_text_value: @recovery_codes.join("\n") }
          ) do
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:copy, class: "w-full h-full") }
            plain "Copy all"
          end
        end

        div(class: "grid grid-cols-2 gap-y-0 px-6 py-5") do
          @recovery_codes.each do |code|
            div(class: "py-[10px] border-b border-gray-50 last:border-0 flex items-center") do
              span(class: "flex w-[12px] h-[12px] text-gray-300 mr-3 flex-shrink-0") do
                render UI::Icon.new(:key, class: "w-full h-full")
              end
              code(class: "text-[13.5px] font-mono font-semibold text-gray-800 tracking-[0.08em]") do
                plain code
              end
            end
          end
        end
      end
    end

    def done_action
      div(class: "flex items-center gap-4") do
        a(
          href: settings_path(tab: "security"),
          class: "inline-flex items-center gap-2 px-5 py-[11px] rounded-xl text-[13px] font-semibold text-white no-underline transition-opacity hover:opacity-90",
          style: "background:#{BRAND}"
        ) do
          span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:check_circle, class: "w-full h-full") }
          plain "I've saved my codes — done"
        end
      end
    end
  end
end
