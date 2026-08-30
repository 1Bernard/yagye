# frozen_string_literal: true

module Settings
  class IndexView < ApplicationComponent
    include UI::Theme

    NAV_GROUPS = [
      {
        label: "Account",
        items: [
          { key: "profile",       label: "Profile",       icon: :user   },
          { key: "security",      label: "Security",      icon: :shield },
          { key: "notifications", label: "Notifications", icon: :bell   }
        ]
      },
      {
        label: "Access",
        items: [
          { key: "allowlists", label: "Allowlists", icon: :lock }
        ]
      }
    ].freeze

    # Simplified 7×7 finder-pattern used as TOTP QR placeholder
    QR_PATTERN = [
      1, 1, 1, 1, 1, 0, 1,
      1, 0, 0, 0, 1, 0, 0,
      1, 0, 1, 0, 1, 1, 1,
      1, 0, 0, 0, 1, 0, 1,
      1, 1, 1, 1, 1, 0, 0,
      0, 0, 0, 1, 0, 1, 0,
      1, 0, 1, 0, 1, 1, 1
    ].flatten.freeze

    NOTIFICATIONS = [
      { key: "payment_success",  label: "Payment received",   desc: "When a customer's payment settles" },
      { key: "payment_failed",   label: "Payment failed",     desc: "When a payment attempt fails" },
      { key: "dispute_opened",   label: "Dispute opened",     desc: "When a customer raises a dispute" },
      { key: "dispute_resolved", label: "Dispute resolved",   desc: "When a dispute is closed" },
      { key: "kyb_status",       label: "KYB status update",  desc: "When your KYB application status changes" },
      { key: "new_team_member",  label: "New team member",    desc: "When someone joins your team" },
      { key: "api_key_created",  label: "API key generated",  desc: "When a new API key is created" },
      { key: "login_new_device", label: "New device sign-in", desc: "When a sign-in occurs from a new browser or device" }
    ].freeze

    def initialize(tab: "profile", current_user: nil, roles: [], ip_allowlists: [], msisdn_allowlists: [], audit_events: [])
      @tab               = tab
      @current_user      = current_user
      @roles             = roles
      @ip_allowlists     = ip_allowlists
      @msisdn_allowlists = msisdn_allowlists
      @audit_events      = audit_events
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :settings,
        title:      "Settings",
        breadcrumbs: [
          { label: "Settings", href: settings_path },
          { label: current_tab_label }
        ]
      ) do
        div(class: "flex gap-10 items-start") do
          settings_sidebar
          div(class: "flex-1 min-w-0") do
            case @tab
            when "profile"       then profile_panel
            when "security"      then security_panel
            when "notifications" then notifications_panel
            when "allowlists"    then allowlists_panel
            end
          end
        end
      end
    end

    private

    # ── Settings sidebar ──────────────────────────────────────────────────────

    def current_tab_label
      NAV_GROUPS.flat_map { |g| g[:items] }.find { |i| i[:key] == @tab }&.dig(:label) || @tab.capitalize
    end

    def settings_sidebar
      nav(class: "w-[172px] flex-shrink-0 sticky top-6 flex flex-col gap-5") do
        NAV_GROUPS.each { |group| sidebar_group(group) }
      end
    end

    def sidebar_group(group)
      div do
        p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-[0.07em] mb-[6px] px-3") do
          plain group[:label]
        end
        div(class: "flex flex-col gap-[2px]") do
          group[:items].each { |item| sidebar_link(item) }
        end
      end
    end

    def sidebar_link(item)
      active = @tab == item[:key]

      if active
        a(href:  settings_path(tab: item[:key]),
          class: "flex items-center gap-[10px] px-3 py-[8px] rounded-[10px] text-[13px] font-semibold no-underline transition-colors",
          style: "background:rgba(61,71,245,0.09);color:#{BRAND}") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0",
               style: "color:#{BRAND}") do
            render UI::Icon.new(item[:icon], class: "w-full h-full")
          end
          plain item[:label]
        end
      else
        a(href:  settings_path(tab: item[:key]),
          class: "flex items-center gap-[10px] px-3 py-[8px] rounded-[10px] text-[13px] font-medium text-gray-500 hover:bg-gray-50 hover:text-gray-700 no-underline transition-colors") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0 text-gray-400") do
            render UI::Icon.new(item[:icon], class: "w-full h-full")
          end
          plain item[:label]
        end
      end
    end

    # ── Profile tab ───────────────────────────────────────────────────────────

    def profile_panel
      render UI::Grid.new(columns: :sidebar) do
        div(class: "flex flex-col gap-5") do
          profile_hero_card
          personal_info_card
          preferences_card
        end
        div(class: "flex flex-col gap-5") do
          account_overview_card
          activity_log_card
        end
      end
    end

    def profile_hero_card
      u          = @current_user
      kind_staff = u&.internal_staff?
      joined     = u&.created_at&.strftime("%d %b %Y")      || "—"
      last_seen  = u&.last_sign_in_at&.strftime("%d %b %Y") || "Never"
      sign_ins   = u&.sign_in_count&.to_s                   || "0"

      div(class: "bg-white border border-gray-100 rounded-2xl px-7 py-7") do
        # ── Avatar + identity ─────────────────────────────────────────────
        div(class: "flex items-start gap-5 mb-6") do
          div(class: "relative flex-shrink-0") do
            render UI::Avatar.new(initials, size: :xl)
            div(class: "absolute -bottom-[3px] -right-[3px] w-5 h-5 rounded-full bg-green-500 border-2 border-white")
          end
          div(class: "flex-1 min-w-0 pt-1") do
            div(class: "flex items-center gap-2 flex-wrap mb-0.5") do
              h2(class: "text-[18px] font-bold text-gray-900 tracking-[-0.02em]") do
                plain u ? "#{u.first_name} #{u.last_name}".strip : "Your Account"
              end
            end
            div(class: "flex items-center gap-2 mt-1 flex-wrap") do
              if kind_staff
                span(class: "badge-blue text-[11px] font-semibold px-[9px] py-[3px] rounded-full") do
                  plain "Yagye Staff"
                end
              else
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full") do
                  plain "Merchant user"
                end
              end
              unless @roles.empty?
                span(class: TYPE_CAPTION) { plain "·" }
                span(class: TYPE_CAPTION) { plain @roles.first&.name }
              end
            end
            p(class: "#{TYPE_CAPTION} mt-1") { plain u&.email || "" }
          end
          render UI::Button.new(variant: :secondary,
                 data: { action: "click->dialog#open", dialog_target_param: "edit-profile-dialog" }) do
            render UI::Icon.new(:edit, class: ICON_SM)
            plain "Edit"
          end
          edit_profile_dialog
        end

        # ── Meta stats ────────────────────────────────────────────────────
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          profile_stat("Joined",      joined,    :calendar)
          profile_stat("Last active", last_seen, :clock)
          profile_stat("Sign-ins",    sign_ins,  :check_circle)
        end
      end
    end

    def profile_stat(label, value, icon)
      div(class: "bg-white px-4 py-3 flex items-center gap-3") do
        div(class: "w-7 h-7 rounded-[8px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-3 h-3 text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-px") { plain label }
          p(class: "text-[12.5px] font-semibold text-gray-900") { plain value }
        end
      end
    end

    def personal_info_card
      u = @current_user
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Personal information" }
        end
        info_field(:user,  "Full name",  "#{u&.first_name} #{u&.last_name}".strip.presence || "—")
        info_field(:mail,  "Email",      u&.email || "—", locked: true)
        info_field(:phone, "Phone",      "Not set", muted: true)
        info_field(:globe, "Timezone",   "Not set", muted: true)
      end
    end

    # ── Preferences card (theme + language) ──────────────────────────────────

    def preferences_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-[18px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Appearance & language" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Your personal display preferences — only visible to you." }
        end
        div(class: "px-6 py-5 flex flex-col gap-5") do
          theme_picker_section
          language_picker_section
        end
      end
    end

    def theme_picker_section
      div(data: { controller: "theme" }) do
        p(class: "#{TYPE_MICRO} mb-3") { plain "Theme" }
        div(class: "flex gap-1 bg-gray-100 p-[5px] rounded-xl") do
          theme_pill("system", "🖥",  "System")
          theme_pill("light",  "☀️",   "Light")
          theme_pill("dark",   "🌑",  "Dark")
        end
      end
    end

    def theme_pill(value, emoji, label)
      active      = (@current_user&.theme_preference.presence || "system") == value
      pill_action = { action: "click->theme#set", theme_value_param: value }
      form(action: settings_profile_path, method: "post", class: "flex-1") do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "theme_preference",   value: value)
        if active
          button(type: "submit",
                 data: pill_action,
                 class: "w-full flex items-center justify-center gap-[6px] px-3 py-[8px] " \
                        "rounded-[9px] bg-white text-[12.5px] font-semibold border-0 cursor-pointer transition-all",
                 style: "color:#{BRAND};box-shadow:0 1px 4px rgba(0,0,0,0.10),0 1px 2px rgba(0,0,0,0.06)") do
            span(style: "font-size:15px;line-height:1;flex-shrink:0") { plain emoji }
            plain label
          end
        else
          button(type: "submit",
                 data: pill_action,
                 class: "w-full flex items-center justify-center gap-[6px] px-3 py-[8px] " \
                        "rounded-[9px] text-[12.5px] font-medium text-gray-500 " \
                        "hover:text-gray-700 border-0 bg-transparent cursor-pointer transition-colors") do
            span(style: "font-size:15px;line-height:1;flex-shrink:0") { plain emoji }
            plain label
          end
        end
      end
    end

    def language_picker_section
      div do
        p(class: "#{TYPE_MICRO} mb-3") { plain "Language" }
        div(class: "grid grid-cols-2 gap-2") do
          language_card("en", "🇬🇧", "English",  "Portal language")
          language_card("fr", "🇫🇷", "Français", "Langue du portail")
        end
      end
    end

    def language_card(code, flag, name, subtitle)
      active = (@current_user&.language_preference || "en") == code
      form(action: settings_profile_path, method: "post") do
        input(type: "hidden", name: "_method",             value: "patch")
        input(type: "hidden", name: "authenticity_token",  value: form_authenticity_token)
        input(type: "hidden", name: "language_preference", value: code)
        if active
          button(type: "submit",
                 class: "flex items-center gap-3 w-full px-4 py-[11px] rounded-xl " \
                        "text-left cursor-pointer transition-all border",
                 style: "border-color:rgba(61,71,245,0.4);background:rgba(61,71,245,0.04)") do
            span(style: "font-size:20px;line-height:1;flex-shrink:0") { plain flag }
            div(class: "flex-1 min-w-0 text-left") do
              p(class: "text-[13px] font-semibold",
                style: "color:#{BRAND}") { plain name }
              p(class: TYPE_CAPTION) { plain "Active" }
            end
            span(class: "flex w-[14px] h-[14px] flex-shrink-0",
                 style: "color:#{BRAND}") do
              render UI::Icon.new(:check, class: "w-full h-full")
            end
          end
        else
          button(type: "submit",
                 class: "flex items-center gap-3 w-full px-4 py-[11px] rounded-xl border border-gray-200 " \
                        "bg-white text-left cursor-pointer transition-all hover:border-gray-300") do
            span(style: "font-size:20px;line-height:1;flex-shrink:0") { plain flag }
            div(class: "flex-1 min-w-0 text-left") do
              p(class: "text-[13px] font-medium text-gray-700") { plain name }
              p(class: TYPE_CAPTION) { plain subtitle }
            end
          end
        end
      end
    end

    def info_field(icon, label, value, locked: false, muted: false)
      div(class: "flex items-center gap-4 px-6 py-[13px] border-b border-gray-50 last:border-0") do
        div(class: "w-[30px] h-[30px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        span(class: "text-[12px] text-gray-400 w-28 flex-shrink-0") { plain label }
        div(class: "flex items-center gap-2 flex-1") do
          span(class: "#{muted ? TYPE_CAPTION : TYPE_BODY_MD}") { plain value }
          if locked
            span(class: "flex w-3 h-3 text-gray-300") do
              render UI::Icon.new(:lock, class: "w-full h-full")
            end
          end
        end
      end
    end

    def edit_profile_dialog
      dialog(id: "edit-profile-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[460px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Edit profile" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Update your name and contact details." }
        end
        form(action: settings_profile_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-4") do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          div(class: "grid grid-cols-2 gap-3") do
            render UI::InputField.new(name: "first_name", label: "First name",
                                      value: @current_user&.first_name)
            render UI::InputField.new(name: "last_name",  label: "Last name",
                                      value: @current_user&.last_name)
          end
          render UI::InputField.new(name: "email", label: "Email address", type: "email",
                                    value: @current_user&.email, readonly: true)
          p(class: TYPE_CAPTION) do
            plain "Email changes require identity verification. Contact support to update."
          end
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "edit-profile-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Save changes"
            end
          end
        end
      end
    end

    def account_overview_card
      u      = @current_user
      totp   = u&.otp_required_for_login
      score  = totp ? 85 : 50
      color  = totp ? "#16a34a" : "#d97706"
      bg     = totp ? "rgba(22,163,74,0.07)" : "rgba(217,119,6,0.07)"
      border = totp ? "rgba(22,163,74,0.28)" : "rgba(217,119,6,0.28)"

      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-5 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Account overview" }
        end

        # Security score
        div(class: "px-5 py-4 border-b border-gray-50") do
          p(class: "#{TYPE_MICRO} mb-3 text-gray-400 uppercase tracking-widest") { plain "Security" }
          div(class: "flex items-center gap-3 rounded-xl px-[14px] py-3",
              style: "background:#{bg};border:1px solid #{border}") do
            div(class: "w-[38px] h-[38px] rounded-full flex-shrink-0 flex items-center justify-center p-[4px]",
                style: "background:conic-gradient(#{color} #{(score * 3.6).round(1)}deg, rgba(128,128,128,0.18) #{(score * 3.6).round(1)}deg)") do
              div(class: "w-full h-full rounded-full bg-white flex items-center justify-center") do
                span(class: "text-[9.5px] font-bold",
                     style: "color:#{color}") { plain "#{score}%" }
              end
            end
            div(class: "flex-1") do
              p(class: TYPE_BODY_MD) { plain "#{score}% secured" }
              p(class: TYPE_CAPTION) { plain totp ? "2FA is active" : "Enable 2FA to improve" }
            end
            a(href: settings_path(tab: "security"),
              class: "flex w-6 h-6 items-center justify-center text-gray-400 hover:text-gray-600 flex-shrink-0") do
              render UI::Icon.new(:chev_right, class: "w-4 h-4")
            end
          end
        end

        # 2FA status
        div(class: "px-5 py-4 border-b border-gray-50") do
          div(class: "flex items-center justify-between") do
            div(class: "flex items-center gap-2") do
              div(class: "w-6 h-6 rounded-[6px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[11px] h-[11px] text-gray-400") do
                  render UI::Icon.new(:shield, class: "w-full h-full")
                end
              end
              span(class: TYPE_BODY_MD) { plain "Two-factor auth" }
            end
            if totp
              span(class: "badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Enabled" }
            else
              span(class: "badge-amber text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Disabled" }
            end
          end
        end

        # Roles
        div(class: "px-5 py-4 border-b border-gray-50") do
          p(class: "#{TYPE_MICRO} mb-3 text-gray-400 uppercase tracking-widest") { plain "Roles" }
          if @roles.empty?
            p(class: TYPE_CAPTION) { plain "No roles assigned." }
          else
            div(class: "flex flex-wrap gap-1.5") do
              @roles.each do |role|
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full") do
                  plain role.name
                end
              end
            end
          end
        end

        # Quick nav links
        div do
          div(class: "px-5 pt-4 pb-[10px]") do
            p(class: TYPE_MICRO) { plain "Navigate" }
          end
          div(class: "divide-rows pb-[6px]") do
            quick_nav_link("Security",       "2FA, sessions & password", :shield, "amber",  settings_path(tab: "security"))
            quick_nav_link("Notifications",  "Alerts & preferences",     :bell,   "purple", settings_path(tab: "notifications"))
            quick_nav_link("Allowlists",     "IPs & MSISDNs",            :lock,   "teal",   settings_path(tab: "allowlists"))
            quick_nav_link("API & Webhooks", "Keys & endpoints",         :key,    "brand",  developers_path)
            quick_nav_link("Team",           "Members & roles",          :users,  "green",  team_users_path)
          end
        end
      end
    end

    def quick_nav_link(label, sub, icon, palette, href)
      a(href: href,
        class: "group flex items-center gap-3 px-5 py-[11px] hover:bg-gray-50 transition-colors no-underline") do
        div(class: "w-[30px] h-[30px] rounded-[9px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
          span(class: "flex w-[13px] h-[13px]") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight") { plain label }
          p(class: "text-[11px] text-gray-400 leading-tight mt-px") { plain sub }
        end
        span(class: "flex w-[13px] h-[13px] text-gray-300 group-hover:text-gray-500 " \
                    "group-hover:translate-x-0.5 transition-all flex-shrink-0") do
          render UI::Icon.new(:chev_right, class: "w-full h-full")
        end
      end
    end

    def activity_log_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-5 py-5 border-b border-gray-100 flex items-center justify-between") do
          div do
            p(class: TYPE_TITLE) { plain "Recent activity" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Your latest account actions." }
          end
        end

        if @audit_events.empty?
          div(class: "px-5 py-10 text-center") do
            div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center mx-auto mb-3") do
              span(class: "flex w-4 h-4 text-gray-400") do
                render UI::Icon.new(:clock, class: "w-full h-full")
              end
            end
            p(class: "#{TYPE_BODY_MD} mb-1") { plain "No activity yet" }
            p(class: TYPE_CAPTION) { plain "Actions like sign-ins and password changes appear here." }
          end
        else
          div(class: "divide-rows") do
            @audit_events.each do |event|
              activity_event_row(event)
            end
          end
        end
      end
    end

    def activity_event_row(event)
      div(class: "flex items-center gap-3 px-5 py-[11px]") do
        div(class: "w-[30px] h-[30px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(event.icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-medium text-gray-800 leading-tight") { plain event.label }
          p(class: TYPE_CAPTION) do
            plain event.ip_address.present? ? "from #{event.ip_address}" : "—"
          end
        end
        span(class: "text-[11px] text-gray-400 flex-shrink-0 tabular-nums") do
          plain event.created_at.strftime("%d %b, %H:%M")
        end
      end
    end

    # ── Security tab ──────────────────────────────────────────────────────────

    def security_panel
      totp_on = @current_user&.otp_required_for_login
      score   = totp_on ? 85 : 50

      div(class: "flex flex-col gap-5") do
        security_health_card(score, totp_on)
        authentication_card(totp_on)
        sessions_card
      end
    end

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
          div(class: "h-[5px] rounded-full overflow-hidden",
              style: "background:rgba(128,128,128,0.18)") do
            div(class: "h-full rounded-full",
                style: "width:#{score}%;background:#{color};transition:width 600ms ease")
          end
        end
        unless totp_on
          render UI::Button.new(variant: :primary) do
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
          span(class: "text-[11px] font-bold leading-none",
               style: "color:#{color}") { plain "#{score}%" }
        end
      end
    end

    def authentication_card(totp_on)
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Authentication" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Manage how you verify your identity when signing in." }
        end

        # ── Password ─────────────────────────────────────────────────────
        div(class: "px-6 pt-5 pb-5 border-b border-gray-100") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Password" }
          div(class: "flex items-center gap-4") do
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
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#open", dialog_target_param: "change-password-dialog" }) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Change"
            end
          end
          change_password_dialog
        end

        # ── Two-step verification ────────────────────────────────────────
        div(class: "px-6 pt-5 pb-5") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Two-step verification" }
          div(class: "flex flex-col gap-[10px] mb-5") do
            auth_method_row("Authenticator app (TOTP)", :shield,
                            desc: "Google Authenticator, Authy, 1Password",
                            checked: totp_on)
            auth_method_row("SMS / phone number", :phone,
                            desc: "Receive a one-time code via text message",
                            coming_soon: true)
            auth_method_row("Email one-time code", :mail,
                            desc: "Receive a code to your email address",
                            coming_soon: true)
          end
          totp_setup_panel unless totp_on
        end
      end
    end

    def auth_method_row(label, icon, desc: nil, checked: false, coming_soon: false)
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
        toggle_checkbox("auth_#{label.downcase.gsub(/\W+/, '_')}", checked: checked)
      end
    end

    def totp_setup_panel
      div(class: "rounded-2xl border border-dashed border-gray-200 p-5",
          style: "background:rgba(61,71,245,0.02)") do
        div(class: "flex items-start gap-5") do
          qr_code_placeholder
          div(class: "flex-1 min-w-0") do
            p(class: "text-[13px] font-semibold text-gray-900 mb-[3px]") { plain "Set up authenticator app" }
            p(class: TYPE_CAPTION) do
              plain "Open Google Authenticator, Authy, or 1Password. Scan the QR code, then enter the 6-digit code to verify."
            end
            div(class: "flex gap-2 mt-[14px]") do
              6.times do |i|
                input(type: "text", maxlength: "1", inputmode: "numeric",
                      pattern: "[0-9]*", autocomplete: i == 0 ? "one-time-code" : "off",
                      class: "w-10 h-11 rounded-xl border border-gray-200 text-center text-[16px] font-semibold text-gray-900 bg-white outline-none",
                      style: "transition:border-color 150ms,box-shadow 150ms;caret-color:#{BRAND}",
                      data: { otp_index: i })
              end
            end
            div(class: "flex items-center gap-4 mt-4") do
              render UI::Button.new(variant: :primary) do
                render UI::Icon.new(:check_circle, class: ICON_SM)
                plain "Verify & enable"
              end
              a(href: "#", class: "text-[12.5px] font-medium no-underline",
                style: "color:#{BRAND}") { plain "View setup guide" }
            end
          end
        end
      end
    end

    def qr_code_placeholder
      div(class: "w-[88px] h-[88px] rounded-xl bg-white border border-gray-100 p-[10px] flex-shrink-0") do
        div(class: "grid gap-[2.5px] w-full h-full",
            style: "grid-template-columns:repeat(7,1fr)") do
          QR_PATTERN.each do |bit|
            div(class: "rounded-[1.5px]",
                style: "background:#{bit == 1 ? '#1f2937' : 'transparent'}")
          end
        end
      end
    end

    def change_password_dialog
      dialog(id: "change-password-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Change password" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Use a strong password you don't use elsewhere." }
        end
        form(action: settings_password_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-4") do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "current_password",      label: "Current password", type: "password")
          render UI::InputField.new(name: "password",              label: "New password",     type: "password")
          render UI::InputField.new(name: "password_confirmation", label: "Confirm password", type: "password")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "change-password-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:shield, class: ICON_SM)
              plain "Update password"
            end
          end
        end
      end
    end

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
                      sub:   "This device · #{Time.current.strftime('%d %b %Y')}",
                      current: true)
        else
          sign_ins.first(5).each_with_index do |evt, i|
            label = evt.user_agent.to_s.split("/").first.presence || "Browser"
            ip    = evt.ip_address.presence || "Unknown location"
            date  = evt.created_at.strftime("%d %b %Y, %H:%M")
            session_row(
              label:   label,
              sub:     "#{ip} · #{date}",
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
               class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 hover:text-red-500 hover:bg-red-50 transition-colors border-0 bg-transparent cursor-pointer ml-1 opacity-0 group-hover:opacity-100") do
          span(class: "flex w-[14px] h-[14px]") do
            render UI::Icon.new(:x, class: "w-full h-full")
          end
        end
      end
    end

    # ── Notifications tab ─────────────────────────────────────────────────────

    def notifications_panel
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        # Header
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Notification preferences" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Choose which events alert you and how you receive them." }
        end

        # ── Events section ─────────────────────────────────────────────────
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-center justify-between mb-[18px]") do
            p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest") { plain "Alert me when…" }
            a(href: "#", class: "text-[11px] font-semibold no-underline",
              style: "color:#{BRAND}") { plain "Select all" }
          end
          div(class: "flex flex-col") do
            NOTIFICATIONS.each { |notif| notification_event_row(notif) }
          end
        end

        # ── Delivery channels section ──────────────────────────────────────
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") { plain "Delivery channels" }
          notification_channel_row(:mail,  "Email",
                                   "Send to #{@current_user&.email || 'your email address'}",
                                   checked: true)
          notification_channel_row(:bell,  "In-app",
                                   "Alerts and badges inside the portal",
                                   checked: true)
          notification_channel_row(:phone, "SMS",
                                   "Text message to your registered phone number",
                                   coming_soon: true)
        end

        # Footer
        div(class: "px-6 py-4 bg-gray-100 border-t border-gray-100 flex justify-end") do
          render UI::Button.new(variant: :primary) do
            render UI::Icon.new(:check, class: ICON_SM)
            plain "Save preferences"
          end
        end
      end
    end

    def notification_event_row(notif)
      label(class: "flex items-center gap-4 py-[10px] px-3 -mx-3 rounded-xl hover:bg-gray-50/70 cursor-pointer transition-colors group") do
        # Native checkbox — accent-color makes it use brand color on check
        input(type: "checkbox", name: "notifications[#{notif[:key]}]", value: "1", checked: true,
              class: "flex-shrink-0 cursor-pointer rounded-[4px] w-[15px] h-[15px]",
              style: "accent-color:#{BRAND}")
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain notif[:label] }
          p(class: TYPE_CAPTION) { plain notif[:desc] }
        end
      end
    end

    def notification_channel_row(icon, label_text, desc, checked: false, coming_soon: false)
      div(class: "flex items-center gap-4 py-[13px] border-b border-gray-50 last:border-0 #{coming_soon ? 'opacity-50' : ''}") do
        div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[15px] h-[15px] text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2") do
            p(class: TYPE_BODY_MD) { plain label_text }
            if coming_soon
              span(class: "badge-gray text-[10px] font-semibold px-[7px] py-[2px] rounded-full") { plain "Coming soon" }
            end
          end
          p(class: TYPE_CAPTION) { plain desc }
        end
        toggle_checkbox("channel_#{label_text.downcase}", checked: coming_soon ? false : checked)
      end
    end

    def toggle_checkbox(name, checked: false)
      bg = checked ? BRAND : BORDER_MED
      label(class: "relative cursor-pointer block") do
        input(type: "checkbox", name: name, class: "sr-only", checked: checked)
        div(class: "w-9 h-5 rounded-full relative transition-[background] duration-150",
            style: "background:#{bg}") do
          div(class: "absolute top-[2px] w-4 h-4 rounded-full bg-white shadow-sm transition-[left] duration-150",
              style: "left:#{checked ? '18px' : '2px'}")
        end
      end
    end

    # ── Allowlists tab ────────────────────────────────────────────────────────

    def allowlists_panel
      div(class: "flex flex-col gap-5") do
        ip_allowlist_card
        msisdn_allowlist_card
      end
    end

    # ── IP allowlist ───────────────────────────────────────────────────────────

    def ip_allowlist_card
      count = @ip_allowlists.size
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start gap-3") do
            div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0 mt-px") do
              span(class: "flex w-[15px] h-[15px] text-gray-400") do
                render UI::Icon.new(:globe, class: "w-full h-full")
              end
            end
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-2 mb-[2px]") do
                p(class: TYPE_TITLE) { plain "IP allowlist" }
                if count > 0
                  span(class: "text-[11px] font-semibold text-gray-500 bg-gray-100 px-[9px] py-[2px] rounded-full") do
                    plain "#{count} #{count == 1 ? 'entry' : 'entries'}"
                  end
                else
                  span(class: "badge-green text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Open access" }
                end
              end
              p(class: TYPE_CAPTION) { plain "Restrict portal and API access to specific IP addresses or CIDR ranges." }
            end
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#open", dialog_target_param: "add-ip-dialog" }) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add IP"
            end
            add_ip_dialog
          end
        end

        if @ip_allowlists.empty?
          ip_empty_state
        else
          ip_active_callout(count)
          div(class: "divide-rows") do
            @ip_allowlists.each { |entry| ip_entry_row(entry) }
          end
        end
      end
    end

    def ip_empty_state
      div(class: "px-6 py-10 flex flex-col items-center text-center") do
        div(class: "w-10 h-10 rounded-xl icon-green flex items-center justify-center mb-3") do
          span(class: "flex w-[17px] h-[17px]") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
        end
        p(class: "#{TYPE_BODY_MD} mb-1") { plain "Open access" }
        p(class: TYPE_CAPTION) do
          plain "All IP addresses can reach your portal and API. Add a CIDR to restrict access to known networks."
        end
      end
    end

    def ip_active_callout(count)
      div(class: "px-6 py-[11px] border-b border-amber-100 flex items-center gap-3",
          style: "background:rgba(217,119,6,0.04)") do
        span(class: "flex w-[13px] h-[13px] text-amber-500 flex-shrink-0") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        p(class: "text-[12px] text-amber-800") do
          plain "Access is restricted — only the #{count} listed #{count == 1 ? 'address' : 'addresses'} can reach your portal and API."
        end
      end
    end

    def ip_entry_row(entry)
      badge_label, badge_color, badge_bg = cidr_badge_attrs(entry.cidr)
      div(class: "group flex items-center gap-4 px-6 py-[14px] hover:bg-gray-50/50 transition-colors") do
        div(class: "w-[34px] h-[34px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(:globe, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-[3px]") do
            code(class: "#{TYPE_MONO} text-[12.5px]") { plain entry.cidr }
            span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full flex-shrink-0",
                 style: "color:#{badge_color};background:#{badge_bg}") { plain badge_label }
          end
          p(class: TYPE_CAPTION) do
            parts = []
            parts << entry.label           if entry.label.present?
            parts << "by #{entry.created_by.presence || 'you'}"
            parts << entry.created_at.strftime("%d %b %Y")
            plain parts.join(" · ")
          end
        end
        div(class: "flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0") do
          allowlist_copy_button(entry.cidr)
          allowlist_remove_button(settings_remove_ip_path(entry), "Remove #{entry.cidr} from allowlist?")
        end
      end
    end

    def cidr_badge_attrs(cidr)
      prefix = cidr.include?("/") ? cidr.split("/").last.to_i : 32
      if prefix == 32
        [ "Single IP",     "#16a34a", "#f0fdf4" ]
      elsif prefix >= 24
        [ "/#{prefix} range", "#d97706", "#fffbeb" ]
      else
        [ "/#{prefix} range", "#dc2626", "#fef2f2" ]
      end
    end

    # ── MSISDN allowlist ───────────────────────────────────────────────────────

    def msisdn_allowlist_card
      count = @msisdn_allowlists.size
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start gap-3") do
            div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0 mt-px") do
              span(class: "flex w-[15px] h-[15px] text-gray-400") do
                render UI::Icon.new(:phone, class: "w-full h-full")
              end
            end
            div(class: "flex-1 min-w-0") do
              div(class: "flex items-center gap-2 mb-[2px]") do
                p(class: TYPE_TITLE) { plain "MSISDN allowlist" }
                if count > 0
                  span(class: "text-[11px] font-semibold text-gray-500 bg-gray-100 px-[9px] py-[2px] rounded-full") do
                    plain "#{count} #{count == 1 ? 'number' : 'numbers'}"
                  end
                else
                  span(class: "badge-green text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Open" }
                end
              end
              p(class: TYPE_CAPTION) { plain "Restrict which phone numbers can initiate MoMo payments via your integration." }
            end
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#open", dialog_target_param: "add-msisdn-dialog" }) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add number"
            end
            add_msisdn_dialog
          end
        end

        if @msisdn_allowlists.empty?
          msisdn_empty_state
        else
          msisdn_active_callout(count)
          div(class: "divide-rows") do
            @msisdn_allowlists.each { |entry| msisdn_entry_row(entry) }
          end
        end
      end
    end

    def msisdn_empty_state
      div(class: "px-6 py-10 flex flex-col items-center text-center") do
        div(class: "w-10 h-10 rounded-xl icon-green flex items-center justify-center mb-3") do
          span(class: "flex w-[17px] h-[17px]") do
            render UI::Icon.new(:phone, class: "w-full h-full")
          end
        end
        p(class: "#{TYPE_BODY_MD} mb-1") { plain "Payments open" }
        p(class: TYPE_CAPTION) do
          plain "Any phone number can initiate MoMo payments. Add numbers to restrict to known customers."
        end
      end
    end

    def msisdn_active_callout(count)
      div(class: "px-6 py-[11px] border-b flex items-center gap-3",
          style: "background:rgba(61,71,245,0.04);border-color:rgba(61,71,245,0.12)") do
        span(class: "flex w-[13px] h-[13px] flex-shrink-0",
             style: "color:#{BRAND}") do
          render UI::Icon.new(:info_circle, class: "w-full h-full")
        end
        p(class: "text-[12px]", style: "color:#3730a3") do
          plain "Payments are restricted — only the #{count} listed #{count == 1 ? 'number' : 'numbers'} can initiate MoMo payments."
        end
      end
    end

    def msisdn_entry_row(entry)
      telco = detect_telco(entry.msisdn)
      div(class: "group flex items-center gap-4 px-6 py-[14px] hover:bg-gray-50/50 transition-colors") do
        div(class: "w-[34px] h-[34px] rounded-[9px] bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[13px] h-[13px] text-gray-400") do
            render UI::Icon.new(:phone, class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-[3px]") do
            code(class: "#{TYPE_MONO} text-[12.5px]") { plain entry.msisdn }
            if telco
              t_name, t_color, t_bg = telco
              span(class: "text-[10px] font-semibold px-[7px] py-[2px] rounded-full flex-shrink-0",
                   style: "color:#{t_color};background:#{t_bg}") { plain t_name }
            end
          end
          p(class: TYPE_CAPTION) do
            parts = []
            parts << entry.label           if entry.label.present?
            parts << "by #{entry.created_by.presence || 'you'}"
            parts << entry.created_at.strftime("%d %b %Y")
            plain parts.join(" · ")
          end
        end
        div(class: "flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0") do
          allowlist_copy_button(entry.msisdn)
          allowlist_remove_button(settings_remove_msisdn_path(entry), "Remove #{entry.msisdn} from allowlist?")
        end
      end
    end

    def detect_telco(msisdn)
      local  = msisdn.gsub(/\A\+233/, "0").gsub(/\A233/, "0")
      prefix = local[0, 3]
      case prefix
      when "024", "054", "055", "059" then [ "MTN",    "#92400e", "#fef3c7" ]
      when "020", "050"               then [ "Telecel", "#991b1b", "#fee2e2" ]
      when "027", "057", "026", "056" then [ "AT",      "#1e40af", "#dbeafe" ]
      end
    end

    # ── Shared allowlist helpers ───────────────────────────────────────────────

    def allowlist_copy_button(value)
      button(type: "button",
             class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 hover:text-gray-600 hover:bg-gray-100 transition-colors border-0 bg-transparent cursor-pointer",
             onclick: "navigator.clipboard.writeText(this.dataset.val);this.classList.add('!text-green-600');setTimeout(()=>this.classList.remove('!text-green-600'),1200)",
             data: { val: value }) do
        span(class: "flex w-[13px] h-[13px]") do
          render UI::Icon.new(:copy, class: "w-full h-full")
        end
      end
    end

    def allowlist_remove_button(path, confirm_text)
      form(action: path, method: "post",
           data: { turbo_confirm: confirm_text }) do
        input(type: "hidden", name: "_method",            value: "delete")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        button(type: "submit",
               class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 hover:text-red-500 hover:bg-red-50 transition-colors border-0 bg-transparent cursor-pointer") do
          span(class: "flex w-[13px] h-[13px]") do
            render UI::Icon.new(:x, class: "w-full h-full")
          end
        end
      end
    end

    # ── Allowlist dialogs ──────────────────────────────────────────────────────

    def add_ip_dialog
      dialog(id: "add-ip-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Add IP to allowlist" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Enter a single IP address or a CIDR range (e.g. 203.0.113.0/24)." }
        end
        form(action: settings_add_ip_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "cidr",  label: "IP address or CIDR",
                                    placeholder: "e.g. 203.0.113.0/24", required: true)
          render UI::InputField.new(name: "label", label: "Label (optional)",
                                    placeholder: "e.g. Office network")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "add-ip-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add IP"
            end
          end
        end
      end
    end

    def add_msisdn_dialog
      dialog(id: "add-msisdn-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Add phone number to allowlist" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Only allowlisted numbers can initiate MoMo payments." }
        end
        form(action: settings_add_msisdn_path, method: "post",
             class: "px-6 py-[22px] flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "msisdn", label: "Phone number (MSISDN)",
                                    placeholder: "e.g. +233241234567", required: true)
          render UI::InputField.new(name: "label",  label: "Label (optional)",
                                    placeholder: "e.g. VIP customer")
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "add-msisdn-dialog" }) do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Cancel"
            end
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add number"
            end
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
