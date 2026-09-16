# frozen_string_literal: true

module Settings
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(tab: "profile", current_user: nil, roles: [], ip_allowlists: [], msisdn_allowlists: [],
                   audit_events: [], sso_configs: [], tier: 1, payout_controls: {})
      @tab               = tab
      @current_user      = current_user
      @roles             = roles
      @ip_allowlists     = ip_allowlists
      @msisdn_allowlists = msisdn_allowlists
      @audit_events      = audit_events
      @sso_configs       = sso_configs
      @tier              = tier
      @payout_controls   = payout_controls
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
                audit_events: @audit_events
              )
            when "security"
              render Settings::SecurityPanel.new(current_user: @current_user, audit_events: @audit_events)
            when "notifications"
              render Settings::NotificationsPanel.new(current_user: @current_user)
            when "allowlists"
              render Settings::AllowlistsPanel.new(
                ip_allowlists: @ip_allowlists, msisdn_allowlists: @msisdn_allowlists
              )
            when "sso"
              render Settings::SsoSection.new(current_user: @current_user, configs: @sso_configs)
            when "verification"
              render Settings::VerificationPanel.new(tier: @tier)
            when "payouts"
              if @current_user&.merchant_user?
                merchant_code = @current_user.merchant_code
                pending_settlements = PortalSettlement
                  .for_merchant(merchant_code)
                  .where(state: %w[pending processing awaiting_approval])
                next_date  = pending_settlements.where.not(value_date: nil).minimum(:value_date)
                unsettled  = pending_settlements.sum(:expected_net)
                currency   = pending_settlements.pick(:currency) || "GHS"
                render Settings::PayoutsPanel.new(
                  controls:        @payout_controls,
                  next_value_date: next_date,
                  unsettled_amount: unsettled,
                  currency:        currency
                )
              end
            end
          end
        end
      end
    end

    private

    def nav_groups
      account_items = [
        { key: "profile",       label: "Profile",       icon: :user   },
        { key: "security",      label: "Security",      icon: :shield },
        { key: "notifications", label: "Notifications", icon: :bell   }
      ]
      if @current_user&.merchant_user?
        account_items << { key: "verification", label: "Verification", icon: :check_circle }
      end

      groups = [
        { label: "Account", items: account_items },
        {
          label: "Access",
          items: [
            { key: "allowlists", label: "Allowlists", icon: :lock }
          ]
        }
      ]

      if @current_user&.merchant_user?
        groups << {
          label: "Finance",
          items: [ { key: "payouts", label: "Payouts", icon: :trending_up } ]
        }
      end

      show_sso = @current_user.internal_staff? ||
                 SsoConfiguration.active_for_email_domain?(@current_user.email.to_s)

      if show_sso
        groups << { label: "Enterprise", items: [{ key: "sso", label: "Single Sign-On", icon: :building }] }
      end

      groups
    end

    def current_tab_label
      nav_groups.flat_map { |g| g[:items] }.find { |i| i[:key] == @tab }&.dig(:label) || @tab.capitalize
    end

    def settings_sidebar
      nav(class: "w-[172px] flex-shrink-0 sticky top-6 flex flex-col gap-5") do
        nav_groups.each { |group| sidebar_group(group) }
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
