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

    def initialize(tab: "profile", current_user: nil, roles: [], ip_allowlists: [], msisdn_allowlists: [], audit_events: [], profile_dialog_open: false)
      @tab                 = tab
      @current_user        = current_user
      @roles               = roles
      @ip_allowlists       = ip_allowlists
      @msisdn_allowlists   = msisdn_allowlists
      @audit_events        = audit_events
      @profile_dialog_open = profile_dialog_open
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
            when "profile"
              render Settings::ProfilePanel.new(
                current_user: @current_user, roles: @roles,
                audit_events: @audit_events, profile_dialog_open: @profile_dialog_open
              )
            when "security"
              render Settings::SecurityPanel.new(current_user: @current_user, audit_events: @audit_events)
            when "notifications"
              render Settings::NotificationsPanel.new(current_user: @current_user)
            when "allowlists"
              render Settings::AllowlistsPanel.new(
                ip_allowlists: @ip_allowlists, msisdn_allowlists: @msisdn_allowlists
              )
            end
          end
        end
      end
    end

    private

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
          span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{BRAND}") do
            render UI::Icon.new(item[:icon], class: "w-full h-full")
          end
          plain item[:label]
        end
      else
        a(href:  settings_path(tab: item[:key]),
          class: "flex items-center gap-[10px] px-3 py-[8px] rounded-[10px] text-[13px] font-medium " \
                 "text-gray-500 hover:bg-gray-50 hover:text-gray-700 no-underline transition-colors") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0 text-gray-400") do
            render UI::Icon.new(item[:icon], class: "w-full h-full")
          end
          plain item[:label]
        end
      end
    end
  end
end
