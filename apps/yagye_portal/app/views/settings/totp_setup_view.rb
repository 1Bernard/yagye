# frozen_string_literal: true

module Settings
  class TotpSetupView < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, otp_secret:, qr_svg:)
      @current_user = current_user
      @otp_secret   = otp_secret
      @qr_svg       = qr_svg
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :settings,
        title: "Enable two-factor authentication",
        breadcrumbs: [
          { label: "Settings", href: settings_path },
          { label: "Security", href: settings_path(tab: "security") },
          { label: "Enable 2FA" }
        ]
      ) do
        div(class: "max-w-[560px] flex flex-col gap-5") do
          qr_card
          verify_card
        end
      end
    end

    private

    # ── Card 1: scan QR ──────────────────────────────────────────────────────

    def qr_card
      render UI::Card.new do |c|
        c.header("Scan with your authenticator app", icon: :smartphone)
        c.body(padding: false) do
          qr_section
          cant_scan_section
        end
      end
    end

    def qr_section
      div(class: "flex flex-col items-center gap-5 px-8 py-8") do
        # QR fills its container; SVG is already white-background — no border needed
        div(class: "w-[216px] [&>svg]:w-full [&>svg]:h-auto rounded-2xl overflow-hidden shadow-[0_2px_16px_rgba(0,0,0,0.07)]") do
          raw safe(@qr_svg)
        end
        div(class: "text-center") do
          p(class: TYPE_BODY_MD) { plain "Point your camera at the code above" }
          p(class: "#{TYPE_CAPTION} mt-[3px] max-w-[320px]") do
            plain "Use Google Authenticator, Authy, 1Password, or any TOTP app."
          end
        end
      end
    end

    def cant_scan_section
      details(class: "border-t border-gray-100 group") do
        summary(class: "flex items-center justify-between px-6 py-4 cursor-pointer list-none select-none hover:bg-gray-50/60 transition-colors") do
          div(class: "flex items-center gap-2") do
            span(class: "flex w-[14px] h-[14px] text-gray-400") do
              render UI::Icon.new(:help, class: "w-full h-full")
            end
            span(class: "text-[12.5px] font-medium text-gray-600") { plain "Can't scan the QR code?" }
          end
          span(class: "flex w-[14px] h-[14px] text-gray-400 transition-transform group-open:rotate-180") do
            render UI::Icon.new(:chev, class: "w-full h-full")
          end
        end

        div(class: "px-6 pb-6") do
          div(class: "rounded-xl bg-gray-50 p-5 flex flex-col gap-3") do
            p(class: TYPE_MICRO) { plain "Manual entry key" }

            div(class: "rounded-lg bg-white border border-gray-100 px-4 py-3") do
              p(class: "font-mono text-[13px] font-semibold text-gray-800 tracking-[0.18em] break-all leading-[1.9] select-all") do
                plain @otp_secret.scan(/.{4}/).join(" ")
              end
            end

            button(
              type: "button",
              class: "self-start flex items-center gap-[6px] text-[12px] font-medium text-gray-500 " \
                     "hover:text-gray-800 transition-colors border border-gray-200 rounded-lg " \
                     "px-[10px] py-[5px] bg-white cursor-pointer",
              data: {
                controller: "clipboard",
                action: "click->clipboard#copy",
                clipboard_text_value: @otp_secret
              }
            ) do
              render UI::Icon.new(:copy, class: "w-[12px] h-[12px]")
              span(data: { clipboard_target: "label" }) { plain "Copy" }
            end

            p(class: TYPE_CAPTION) do
              plain "Enter this key in your authenticator app if you can't scan the QR code."
            end
          end
        end
      end
    end

    # ── Card 2: verify code ───────────────────────────────────────────────────

    def verify_card
      render UI::Card.new do |c|
        c.header("Enter the 6-digit code to verify", icon: :shield)
        c.body do
          p(class: "#{TYPE_CAPTION} mb-5") do
            plain "Your app generates a new code every 30 seconds. Enter the current one to confirm setup."
          end
          verify_form
        end
      end
    end

    def verify_form
      form(
        action: settings_totp_path,
        method: "post",
        class: "flex flex-col gap-6",
        data: { controller: "otp-input" }
      ) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "otp_code", data: { otp_input_target: "combined" })

        div(class: "flex gap-2") do
          6.times do |i|
            input(
              type: "text",
              inputmode: "numeric",
              pattern: "[0-9]*",
              maxlength: "1",
              autocomplete: i.zero? ? "one-time-code" : "off",
              autofocus: i.zero?,
              class: "w-12 rounded-xl border border-gray-200 text-center text-[20px] " \
                     "font-semibold text-gray-900 bg-gray-50 outline-none " \
                     "focus:bg-white focus:border-blue-400 focus:ring-2 focus:ring-blue-500/10 transition-all",
              style: "height:3.25rem;caret-color:#{BRAND}",
              data: { otp_input_target: "digit" }
            )
          end
        end

        div(class: "flex items-center gap-4") do
          render UI::Button.new(variant: :primary, type: "submit") do
            render UI::Icon.new(:check_circle, class: ICON_SM)
            plain "Verify & enable"
          end
          a(href: settings_path(tab: "security"),
            class: "text-[12.5px] font-medium no-underline #{LINK_MUTED}") do
            plain "Cancel"
          end
        end
      end
    end
  end
end
