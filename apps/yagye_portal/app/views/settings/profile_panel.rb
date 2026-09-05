# frozen_string_literal: true

module Settings
  class ProfilePanel < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, roles: [], audit_events: [], profile_dialog_open: false)
      @current_user        = current_user
      @roles               = roles
      @audit_events        = audit_events
      @profile_dialog_open = profile_dialog_open
    end

    def view_template
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

    private

    # ── Profile hero ──────────────────────────────────────────────────────────

    def profile_hero_card
      u         = @current_user
      joined    = u&.created_at&.strftime("%d %b %Y")      || "—"
      last_seen = u&.last_sign_in_at&.strftime("%d %b %Y") || "Never"
      sign_ins  = u&.sign_in_count&.to_s                   || "0"

      div(class: "bg-white border border-gray-100 rounded-2xl px-7 py-7") do
        div(class: "flex items-start gap-5 mb-6") do
          div(class: "relative flex-shrink-0") do
            render UI::Avatar.new(initials, size: :xl)
            div(class: "absolute -bottom-[3px] -right-[3px] w-5 h-5 rounded-full bg-green-500 border-2 border-white")
          end
          div(class: "flex-1 min-w-0 pt-1") do
            h2(class: "text-[18px] font-bold text-gray-900 tracking-[-0.02em] mb-1") do
              plain u ? "#{u.first_name} #{u.last_name}".strip : "Your Account"
            end
            div(class: "flex items-center gap-2 flex-wrap") do
              if u&.internal_staff?
                span(class: "badge-blue text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Yagye Staff" }
              else
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Merchant user" }
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

    def edit_profile_dialog
      dialog(id: "edit-profile-dialog",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[460px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Edit profile" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Update your name and contact details." }
        end
        div(class: "px-6 py-[22px]") do
          render Settings::ProfileForm.new(@current_user,
                                          action: settings_profile_path,
                                          method: :patch)
        end
      end
      if @profile_dialog_open
        script { plain "document.getElementById('edit-profile-dialog').showModal()" }
      end
    end

    # ── Personal info ─────────────────────────────────────────────────────────

    def personal_info_card
      u = @current_user
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Personal information" }
        end
        render UI::DetailRow.new(icon: :user,  label: "Full name", value: "#{u&.first_name} #{u&.last_name}".strip.presence || "—")
        render UI::DetailRow.new(icon: :mail,  label: "Email",     value: u&.email || "—", locked: true)
        render UI::DetailRow.new(icon: :phone, label: "Phone",     value: "Not set")
        render UI::DetailRow.new(icon: :globe, label: "Timezone",  value: "Not set")
      end
    end

    # ── Preferences ───────────────────────────────────────────────────────────

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
      active = (@current_user&.theme_preference.presence || "system") == value
      form(action: settings_profile_path, method: "post", class: "flex-1") do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(type: "hidden", name: "theme_preference",   value: value)
        if active
          button(type: "submit", data: { action: "click->theme#set", theme_value_param: value },
                 class: "w-full flex items-center justify-center gap-[6px] px-3 py-[8px] " \
                        "rounded-[9px] bg-white text-[12.5px] font-semibold border-0 cursor-pointer transition-all",
                 style: "color:#{BRAND};box-shadow:0 1px 4px rgba(0,0,0,0.10),0 1px 2px rgba(0,0,0,0.06)") do
            span(style: "font-size:15px;line-height:1;flex-shrink:0") { plain emoji }
            plain label
          end
        else
          button(type: "submit", data: { action: "click->theme#set", theme_value_param: value },
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
                 class: "flex items-center gap-3 w-full px-4 py-[11px] rounded-xl text-left cursor-pointer transition-all border",
                 style: "border-color:rgba(61,71,245,0.4);background:rgba(61,71,245,0.04)") do
            span(style: "font-size:20px;line-height:1;flex-shrink:0") { plain flag }
            div(class: "flex-1 min-w-0 text-left") do
              p(class: "text-[13px] font-semibold", style: "color:#{BRAND}") { plain name }
              p(class: TYPE_CAPTION) { plain "Active" }
            end
            span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{BRAND}") do
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

    # ── Account overview ──────────────────────────────────────────────────────

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

        # Security score mini-widget
        div(class: "px-5 py-4 border-b border-gray-50") do
          p(class: "#{TYPE_MICRO} mb-3 text-gray-400 uppercase tracking-widest") { plain "Security" }
          div(class: "flex items-center gap-3 rounded-xl px-[14px] py-3",
              style: "background:#{bg};border:1px solid #{border}") do
            div(class: "w-[38px] h-[38px] rounded-full flex-shrink-0 flex items-center justify-center p-[4px]",
                style: "background:conic-gradient(#{color} #{(score * 3.6).round(1)}deg, rgba(128,128,128,0.18) #{(score * 3.6).round(1)}deg)") do
              div(class: "w-full h-full rounded-full bg-white flex items-center justify-center") do
                span(class: "text-[9.5px] font-bold", style: "color:#{color}") { plain "#{score}%" }
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
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain role.name }
              end
            end
          end
        end

        # Quick nav
        div do
          div(class: "px-5 pt-4 pb-[10px]") { p(class: TYPE_MICRO) { plain "Navigate" } }
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
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(icon, class: "w-full h-full") }
        end
        div(class: "flex-1 min-w-0") do
          p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight") { plain label }
          p(class: "text-[11px] text-gray-400 leading-tight mt-px") { plain sub }
        end
        span(class: "flex w-[13px] h-[13px] text-gray-300 group-hover:text-gray-500 group-hover:translate-x-0.5 transition-all flex-shrink-0") do
          render UI::Icon.new(:chev_right, class: "w-full h-full")
        end
      end
    end

    # ── Activity log ──────────────────────────────────────────────────────────

    def activity_log_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-5 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Recent activity" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Your latest account actions." }
        end

        if @audit_events.empty?
          div(class: "px-5 py-10 flex flex-col items-center text-center gap-2") do
            div(class: "w-10 h-10 rounded-xl icon-brand flex items-center justify-center mb-1") do
              span(class: "flex w-5 h-5") { render UI::Icon.new(:clock, class: "w-full h-full") }
            end
            p(class: "#{TYPE_BODY_MD} mb-1") { plain "No activity yet" }
            p(class: TYPE_CAPTION) { plain "Actions like sign-ins and password changes appear here." }
          end
        else
          div(class: "divide-rows") do
            @audit_events.each { |event| activity_event_row(event) }
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
          p(class: TYPE_CAPTION) { plain event.ip_address.present? ? "from #{event.ip_address}" : "—" }
        end
        span(class: "text-[11px] text-gray-400 flex-shrink-0 tabular-nums") do
          plain event.created_at.strftime("%d %b, %H:%M")
        end
      end
    end

    def initials
      return "??" unless @current_user
      [ @current_user.first_name&.first, @current_user.last_name&.first ].compact.join.upcase.presence || "??"
    end
  end
end
