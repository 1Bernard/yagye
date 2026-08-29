# frozen_string_literal: true

module Settings
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "profile",       label: "Profile" },
      { key: "security",      label: "Security" },
      { key: "notifications", label: "Notifications" },
      { key: "allowlists",    label: "Allowlists" }
    ].freeze

    def initialize(tab: "profile", current_user: nil)
      @tab          = tab
      @current_user = current_user
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :settings,
        title:      "Settings",
        breadcrumbs: [ { label: "Settings" } ]
      ) do
        page_header
        tab_bar
        case @tab
        when "profile"       then profile_panel
        when "security"      then security_panel
        when "notifications" then notifications_panel
        when "allowlists"    then allowlists_panel
        end
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:20px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Account" }
          h1(style: TYPE_DISPLAY) { "Settings" }
        end
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href: settings_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    # ── Profile tab ───────────────────────────────────────────────────────────

    def profile_panel
      div(style: "display:grid;grid-template-columns:1fr 340px;gap:24px;align-items:start") do
        profile_form_card
        avatar_card
      end
    end

    def profile_form_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Personal information" }
          p(style: "#{TYPE_CAPTION};margin-top:3px") { "Update your name and contact details." }
        end
        div(style: "padding:24px") do
          div(style: "display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:16px") do
            form_field("First name",  @current_user&.first_name || "", name: "first_name")
            form_field("Last name",   @current_user&.last_name  || "", name: "last_name")
          end
          div(style: "margin-bottom:16px") do
            form_field("Email address", @current_user&.email || "", name: "email", type: "email", readonly: true)
            p(style: "#{TYPE_CAPTION};margin-top:5px") do
              "Email changes require identity verification. Contact support to update."
            end
          end
          div(style: "display:flex;justify-content:flex-end;padding-top:8px") do
            button(type: "submit", class: BTN_PRIMARY) { "Save changes" }
          end
        end
      end
    end

    def avatar_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:24px") do
        p(style: "#{TYPE_TITLE};margin-bottom:16px") { "Profile photo" }
        div(style: "display:flex;flex-direction:column;align-items:center;gap:14px") do
          render UI::Avatar.new(initials, size: :xl)
          p(style: "#{TYPE_CAPTION};text-align:center") { "Avatar from your initials. Photo upload coming soon." }
        end
      end
    end

    def form_field(label, value, name:, type: "text", readonly: false)
      div do
        div(style: "#{TYPE_MICRO};margin-bottom:6px") { label }
        input(type: type, name: name, value: value,
              class: readonly ? "#{INPUT_FIELD} bg-gray-100 cursor-not-allowed" : INPUT_FIELD,
              readonly: readonly)
      end
    end

    # ── Security tab ──────────────────────────────────────────────────────────

    def security_panel
      div(style: "display:flex;flex-direction:column;gap:20px") do
        password_card
        totp_card
        sessions_card
      end
    end

    def password_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Password" }
          p(style: "#{TYPE_CAPTION};margin-top:3px") { "Use a strong, unique password for your account." }
        end
        div(style: "padding:24px;display:flex;flex-direction:column;gap:16px") do
          form_field("Current password", "",    name: "current_password",  type: "password")
          form_field("New password",     "",    name: "new_password",      type: "password")
          form_field("Confirm password", "",    name: "confirm_password",  type: "password")
          div(style: "display:flex;justify-content:flex-end") do
            button(type: "submit", class: BTN_PRIMARY) { "Change password" }
          end
        end
      end
    end

    def totp_card
      totp_on = @current_user&.otp_required_for_login

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:20px 24px") do
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;gap:16px") do
          div do
            p(style: TYPE_TITLE) { "Two-factor authentication" }
            p(style: "#{TYPE_CAPTION};margin-top:3px") do
              "Add an extra layer of security with an authenticator app (TOTP)."
            end
          end
          if totp_on
            div(style: "display:flex;align-items:center;gap:8px;flex-shrink:0") do
              span(style: "width:8px;height:8px;border-radius:50%;background:#16a34a;flex-shrink:0")
              span(style: "font-size:12px;font-weight:600;color:#16a34a") { "Enabled" }
            end
          else
            button(type: "button", class: BTN_SECONDARY) { "Enable TOTP" }
          end
        end
      end
    end

    def sessions_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;justify-content:space-between") do
            p(style: TYPE_TITLE) { "Active sessions" }
            button(type: "button", class: BTN_DANGER) { "Sign out all devices" }
          end
        end
        div(style: "padding:20px 24px") do
          div(style: "display:flex;align-items:center;gap:14px;padding:14px;background:#{SURFACE};" \
                     "border-radius:12px;border:1px solid #{BORDER}") do
            span(style: "display:flex;width:18px;height:18px;color:#{SUBTLE_TEXT}") do
              render UI::Icon.new(:globe, class: "w-full h-full")
            end
            div(style: "flex:1") do
              p(style: TYPE_BODY_MD) { "Current session" }
              p(style: TYPE_CAPTION) { "This device · #{Time.current.strftime('%d %b %Y')}" }
            end
            span(style: "font-size:11px;font-weight:600;color:#16a34a;background:#dcfce7;padding:3px 10px;border-radius:16px") { "Active" }
          end
        end
      end
    end

    # ── Notifications tab ─────────────────────────────────────────────────────

    def notifications_panel
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Notification preferences" }
          p(style: "#{TYPE_CAPTION};margin-top:3px") { "Choose how you receive alerts for key events." }
        end
        notification_matrix
      end
    end

    NOTIFICATIONS = [
      { key: "payment_success",  label: "Payment received",      desc: "When a customer's payment settles" },
      { key: "payment_failed",   label: "Payment failed",        desc: "When a payment attempt fails" },
      { key: "dispute_opened",   label: "Dispute opened",        desc: "When a customer raises a dispute" },
      { key: "dispute_resolved", label: "Dispute resolved",      desc: "When a dispute is closed" },
      { key: "kyb_status",       label: "KYB status update",     desc: "When your KYB application status changes" },
      { key: "new_team_member",  label: "New team member",       desc: "When someone joins your team" },
      { key: "api_key_created",  label: "API key generated",     desc: "When a new API key is created" },
      { key: "login_new_device", label: "New device sign-in",    desc: "When a sign-in occurs from a new browser or device" }
    ].freeze

    def notification_matrix
      div do
        div(style: "display:grid;grid-template-columns:1fr auto auto;gap:0;" \
                   "border-bottom:1px solid #{BORDER};padding:12px 24px") do
          p(style: TYPE_MICRO) { "Event" }
          p(style: "#{TYPE_MICRO};text-align:center;width:80px") { "Email" }
          p(style: "#{TYPE_MICRO};text-align:center;width:80px") { "In-app" }
        end

        NOTIFICATIONS.each do |notif|
          div(style: "display:grid;grid-template-columns:1fr auto auto;align-items:center;" \
                     "padding:14px 24px;border-bottom:1px solid #{BORDER};" \
                     "") do
            div do
              p(style: TYPE_BODY_MD) { notif[:label] }
              p(style: TYPE_CAPTION) { notif[:desc] }
            end
            div(style: "width:80px;display:flex;justify-content:center") do
              toggle_checkbox("#{notif[:key]}_email", checked: true)
            end
            div(style: "width:80px;display:flex;justify-content:center") do
              toggle_checkbox("#{notif[:key]}_inapp", checked: true)
            end
          end
        end

        div(style: "padding:16px 24px;display:flex;justify-content:flex-end;background:#{SURFACE}") do
          button(type: "button", class: BTN_PRIMARY) { "Save preferences" }
        end
      end
    end

    def toggle_checkbox(name, checked: false)
      label(style: "position:relative;cursor:pointer;display:block") do
        input(type: "checkbox", name: name, class: "sr-only", checked: checked)
        div(style: "width:36px;height:20px;border-radius:10px;background:#{checked ? BRAND : BORDER_MED};" \
                   "transition:background 150ms;position:relative") do
          div(style: "position:absolute;top:2px;left:#{checked ? '18px' : '2px'};" \
                     "width:16px;height:16px;border-radius:50%;background:#fff;transition:left 150ms;" \
                     "box-shadow:0 1px 3px rgba(0,0,0,0.2)")
        end
      end
    end

    # ── Allowlists tab ────────────────────────────────────────────────────────

    def allowlists_panel
      div(style: "display:flex;flex-direction:column;gap:20px") do
        ip_allowlist_card
        msisdn_allowlist_card
      end
    end

    def ip_allowlist_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;justify-content:space-between") do
            div do
              p(style: TYPE_TITLE) { "IP allowlist" }
              p(style: "#{TYPE_CAPTION};margin-top:3px") do
                "Restrict portal and API access to specific IP addresses."
              end
            end
            button(type: "button", class: BTN_SECONDARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              "Add IP"
            end
          end
        end
        div(style: "padding:24px") do
          div(style: "background:#{SURFACE};border:1px solid #{BORDER};border-radius:12px;" \
                     "padding:40px 24px;text-align:center") do
            p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "No IP restrictions" }
            p(style: TYPE_CAPTION) { "All IP addresses can access the portal. Add CIDRs to restrict access." }
          end
        end
      end
    end

    def msisdn_allowlist_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;justify-content:space-between") do
            div do
              p(style: TYPE_TITLE) { "MSISDN allowlist" }
              p(style: "#{TYPE_CAPTION};margin-top:3px") do
                "Limit which phone numbers can initiate payments through your integration."
              end
            end
            button(type: "button", class: BTN_SECONDARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              "Add number"
            end
          end
        end
        div(style: "padding:24px") do
          div(style: "background:#{SURFACE};border:1px solid #{BORDER};border-radius:12px;" \
                     "padding:40px 24px;text-align:center") do
            p(style: "#{TYPE_BODY_MD};margin-bottom:6px") { "Allowlist is open" }
            p(style: TYPE_CAPTION) { "Any phone number can pay. Add MSISDNs to restrict to known customers." }
          end
        end
      end
    end

    def initials
      return "??" unless @current_user
      [ @current_user.first_name&.first, @current_user.last_name&.first ].compact.join.upcase.presence || "??"
    end
  end
end
