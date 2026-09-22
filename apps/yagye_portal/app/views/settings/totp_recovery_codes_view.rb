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
      div(class: "mb-6") do
        render UI::Notice.new(
          variant: :warning,
          icon:    :alert_triangle,
          size:    :lg,
          title:   "Save these codes now — you won't see them again.",
          body:    "Each code can be used once to sign in if you lose access to your authenticator app. Store them in a password manager or a secure location."
        )
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
