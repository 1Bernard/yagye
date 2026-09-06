# frozen_string_literal: true

module Settings
  class SecurityPanel < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, audit_events: [])
      @current_user = current_user
      @audit_events = audit_events
    end

    def view_template
      totp_on = @current_user&.otp_required_for_login
      score   = totp_on ? 85 : 50
      div(class: "flex flex-col gap-5") do
        security_health_card(score, totp_on)
        authentication_card(totp_on)
        sessions_card
        render Settings::PasskeysSection.new(current_user: @current_user)
      end
    end

    private

    # ── Security health ───────────────────────────────────────────────────────

    def security_health_card(score, totp_on)
      color  = score >= 80 ? "#16a34a" : "#d97706"
      bg     = score >= 80 ? "rgba(22,163,74,0.07)" : "rgba(217,119,6,0.07)"
      border = score >= 80 ? "rgba(22,163,74,0.28)" : "rgba(217,119,6,0.28)"

      div(class: "rounded-2xl px-6 py-5 flex items-center gap-5",
          style: "background:#{bg};border:1px solid #{border}") do
        score_ring(score, color)
        div(class: "flex-1 min-w-0") do
          p(class: "text-[15px] font-bold text-gray-900") do
            plain "Account security is #{score}%"
          end
          p(class: "#{TYPE_CAPTION} mt-0.5 mb-3") do
            plain(totp_on ? "Your account is well protected. Keep your 2FA recovery codes safe." :
                            "Enable two-factor authentication to strengthen your account.")
          end
          div(class: "h-[5px] rounded-full overflow-hidden", style: "background:rgba(128,128,128,0.18)") do
            div(class: "h-full rounded-full",
                style: "width:#{score}%;background:#{color};transition:width 600ms ease")
          end
        end
        unless totp_on
          render UI::Button.new(variant: :primary, href: settings_totp_new_path) do
            render UI::Icon.new(:shield, class: ICON_SM)
            plain "Enable 2FA"
          end
        end
      end
    end

    def score_ring(score, color)
      deg = (score * 3.6).round(1)
      div(class: "w-[56px] h-[56px] rounded-full flex-shrink-0 flex items-center justify-center p-[5px]",
          style: "background:conic-gradient(#{color} #{deg}deg, rgba(128,128,128,0.18) #{deg}deg)") do
        div(class: "w-full h-full rounded-full bg-white flex items-center justify-center") do
          span(class: "text-[11px] font-bold leading-none", style: "color:#{color}") { plain "#{score}%" }
        end
      end
    end

    # ── Authentication ────────────────────────────────────────────────────────

    def authentication_card(totp_on)
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden",
          data: { controller: "dialog" }) do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Authentication" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Manage how you verify your identity when signing in." }
        end

        # Password section
        div(class: "px-6 pt-5 pb-5 border-b border-gray-100",
            data: { controller: "inline-edit" }) do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Password" }

          # ── Display state ────────────────────────────────────────────────
          div(class: "flex items-center gap-4", data: { inline_edit_target: "display" }) do
            div(class: "flex-1") do
              div(class: "flex items-center gap-3 mb-1") do
                span(class: "text-[20px] leading-none tracking-[0.1em] text-gray-300") { plain "●" * 12 }
                span(class: "badge-green inline-flex items-center gap-[5px] text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0") do
                  span(class: "w-[5px] h-[5px] rounded-full bg-green-600 flex-shrink-0")
                  plain "Very secure"
                end
              end
              p(class: TYPE_CAPTION) do
                plain "Last updated #{@current_user&.updated_at&.strftime('%d %B %Y') || '—'}"
              end
            end
            div(data: { inline_edit_target: "trigger" }) do
              render UI::Button.new(variant: :secondary,
                     data: { action: "click->inline-edit#edit" }) do
                render UI::Icon.new(:edit, class: ICON_SM)
                plain "Change"
              end
            end
          end

          # ── Edit state (hidden) ──────────────────────────────────────────
          div(hidden: true, data: { inline_edit_target: "form" }) do
            form(action: settings_password_path, method: "post",
                 class: "flex flex-col gap-3 pt-1") do
              input(type: "hidden", name: "_method",            value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render UI::InputField.new(name: "current_password", label: "Current password",
                                        type: "password", autocomplete: "current-password")
              render UI::InputField.new(name: "password", label: "New password",
                                        type: "password", autocomplete: "new-password")
              render UI::InputField.new(name: "password_confirmation", label: "Confirm new password",
                                        type: "password", autocomplete: "new-password")
              div(class: "flex items-center gap-3 pt-1") do
                render UI::Button.new(variant: :primary, type: "submit") do
                  render UI::Icon.new(:shield, class: ICON_SM)
                  plain "Update password"
                end
                button(type: "button",
                       class: "text-[12.5px] font-medium text-gray-400 hover:text-gray-700 transition-colors bg-transparent border-0 cursor-pointer p-0",
                       data: { action: "click->inline-edit#cancel" }) do
                  plain "Cancel"
                end
              end
            end
          end
        end

        # 2FA section
        div(class: "px-6 pt-5 pb-5") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Two-step verification" }
          div(class: "flex flex-col gap-[10px]") do
            totp_method_row(totp_on)
            auth_method_row("SMS / phone number", :phone,
                            desc: "Receive a one-time code via text message", coming_soon: true)
            auth_method_row("Email one-time code", :mail,
                            desc: "Receive a code to your email address", coming_soon: true)
          end
          disable_totp_dialog if totp_on
        end
      end
    end

    def totp_method_row(enabled)
      div(class: "flex items-center gap-3") do
        div(class: "w-8 h-8 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[14px] h-[14px] text-gray-400") do
            render UI::Icon.new(:shield, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          span(class: TYPE_BODY_MD) { plain "Authenticator app (TOTP)" }
          p(class: TYPE_CAPTION) { plain "Google Authenticator, Authy, 1Password" }
        end
        if enabled
          render UI::Button.new(variant: :danger,
                 data: { action: "click->dialog#open", dialog_target_param: "disable-totp-dialog" }) do
            render UI::Icon.new(:shield_off, class: ICON_SM)
            plain "Disable"
          end
        else
          render UI::Button.new(variant: :secondary, href: settings_totp_new_path) do
            render UI::Icon.new(:shield, class: ICON_SM)
            plain "Enable"
          end
        end
      end
    end

    def auth_method_row(label, icon, desc: nil, checked: false, coming_soon: false, toggle_href: nil, **toggle_attrs)
      div(class: "flex items-center gap-3 #{coming_soon ? 'opacity-50' : ''}") do
        div(class: "w-8 h-8 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[14px] h-[14px] text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2") do
            span(class: TYPE_BODY_MD) { plain label }
            if coming_soon
              span(class: "badge-gray text-[10px] font-semibold px-[7px] py-[2px] rounded-full") { plain "Coming soon" }
            end
          end
          p(class: TYPE_CAPTION) { plain desc } if desc
        end
        render UI::Toggle.new(name: "auth_#{label.downcase.gsub(/\W+/, '_')}", checked: checked,
                              href: toggle_href, **toggle_attrs)
      end
    end

    def disable_totp_dialog
      dialog(id: "disable-totp-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[400px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Disable two-factor authentication" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Confirm your password to turn off 2FA. Your account will be less secure."
          end
        end
        form(action: settings_totp_delete_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-4") do
          input(type: "hidden", name: "_method",            value: "delete")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "current_password", label: "Current password", type: "password")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "disable-totp-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :danger, type: "submit") do
              render UI::Icon.new(:shield_off, class: ICON_SM)
              plain "Disable 2FA"
            end
          end
        end
      end
    end

    # ── Sessions ──────────────────────────────────────────────────────────────

    def sessions_card
      sign_ins = @audit_events.select { |e| e.event_type == "signed_in" }

      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
          div do
            p(class: TYPE_TITLE) { plain "Browsers & devices" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Recent sign-ins to your account. Remove any you don't recognise."
            end
          end
          render UI::Button.new(variant: :danger) do
            render UI::Icon.new(:logout, class: ICON_SM)
            plain "Sign out all"
          end
        end

        if sign_ins.empty?
          session_row(label: "Current browser",
                      sub: "This device · #{Time.current.strftime('%d %b %Y')}",
                      current: true)
        else
          sign_ins.first(5).each_with_index do |evt, i|
            session_row(
              label:   evt.user_agent.to_s.split("/").first.presence || "Browser",
              sub:     "#{evt.ip_address.presence || 'Unknown location'} · #{evt.created_at.strftime('%d %b %Y, %H:%M')}",
              current: i == 0,
              ago:     i.positive? ? evt.created_at.strftime("%d %b, %H:%M") : nil
            )
          end
        end
      end
    end

    def session_row(label:, sub:, current: false, ago: nil)
      div(class: "group flex items-center gap-4 px-6 py-[14px] border-b border-gray-50 last:border-0 hover:bg-gray-50/60 transition-colors") do
        div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[15px] h-[15px] text-gray-400") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain label }
          p(class: TYPE_CAPTION) { plain sub }
        end
        if current
          span(class: "badge-green text-[11px] font-semibold px-[10px] py-[3px] rounded-full flex-shrink-0") { plain "Current session" }
        else
          span(class: "#{TYPE_CAPTION} flex-shrink-0") { plain ago }
        end
        button(type: "button",
               class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 " \
                      "hover:text-red-500 hover:bg-red-50 transition-colors border-0 bg-transparent " \
                      "cursor-pointer ml-1 opacity-0 group-hover:opacity-100") do
          span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:x, class: "w-full h-full") }
        end
      end
    end
  end
end
