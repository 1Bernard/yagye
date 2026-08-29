# frozen_string_literal: true

module Layout
  class Sidebar < ApplicationComponent
    include UI::Theme

    NAV_SECTIONS = [
      {
        label: "MAIN MENU",
        items: [
          { key: :dashboard,  icon: :home,        label: "Dashboard", path: :authenticated_root_path },
          { key: :payments,   icon: :credit_card, label: "Payments",  path: :payments_path },
          { key: :disputes,   icon: :flag,        label: "Disputes",  path: :disputes_path }
        ]
      },
      {
        label: "TEAM",
        items: [
          { key: :team_users, icon: :users,  label: "Users",             path: :team_users_path },
          { key: :team_roles, icon: :shield, label: "Roles & Permissions", path: :team_roles_path }
        ]
      },
      {
        label: "OPERATIONS",
        internal_only: true,
        items: [
          { key: :merchants,   icon: :building, label: "Merchants",  path: :merchants_path },
          { key: :kyb_reviews, icon: :shield,   label: "KYB Review", path: :kyb_reviews_path }
        ]
      },
      {
        label: "ACCOUNT",
        items: [
          { key: :developers, icon: :key,      label: "API Keys",       path: :developers_path },
          { key: :settings,   icon: :settings, label: "Settings",       path: :settings_path },
          { key: :help,       icon: :headset,  label: "Help & Support", path: :help_path }
        ]
      }
    ].freeze

    def initialize(active:)
      @active = active
    end

    def view_template
      # Width is managed by .sidebar-wrapper CSS (240px) and .sidebar-collapsed (64px).
      # h-full fills the h-screen overflow-hidden parent set in Shell.
      nav(class: "sidebar-wrapper bg-white border-r border-gray-100 flex flex-col h-full flex-shrink-0",
          data: { controller: "sidebar" }) do
        logo_block
        div(class: "flex-1 overflow-y-auto overflow-x-hidden") do
          div(class: "py-4") do
            NAV_SECTIONS.each { |s| nav_section(s) }
          end
        end
        tier_card if show_tier_card?
        mode_toggle if show_mode_toggle?
        user_row
      end
    end

    private

    # ── Logo block: exactly 56px to align border-bottom with topbar ────────────

    def logo_block
      # sidebar-logo-block lets CSS adjust padding in collapsed mode
      div(class: "sidebar-logo-block",
          style: "display:flex;align-items:center;justify-content:space-between;" \
                 "height:56px;border-bottom:1px solid #{BORDER};flex-shrink:0;overflow:hidden") do
        # Full text logo — visible when expanded, hidden when collapsed
        img(src: asset_path("yagye-text.png"),
            alt: "Yagye",
            class: "sidebar-logo-full",
            style: "height:26px;width:auto;object-fit:contain;flex-shrink:0")

        # Icon-only logo — hidden when expanded, visible when collapsed
        img(src: asset_path("yagye.png"),
            alt: "Yagye",
            class: "sidebar-logo-icon",
            style: "width:28px;height:28px;object-fit:contain;flex-shrink:0")

        # Collapse toggle — left chevron = collapse, right = expand
        button(type: "button",
               class: "sidebar-collapse-btn topbar-icon-btn",
               style: "display:flex;align-items:center;justify-content:center;width:26px;height:26px;" \
                      "border-radius:7px;flex-shrink:0;color:#{SUBTLE_TEXT}",
               data:  { action: "click->sidebar#toggle" },
               title: "Toggle sidebar") do
          span(class: "sidebar-collapse-icon",
               style: "display:flex;width:14px;height:14px") do
            render UI::Icon.new(:chev, class: "w-full h-full")
          end
        end
      end
    end

    # ── Nav sections ────────────────────────────────────────────────────────────

    def nav_section(section)
      return if section[:internal_only] && !internal_staff?

      div(class: "px-3 mb-2") do
        p(class: "sidebar-section-label #{LABEL} px-2 mb-1") { section[:label] }
        section[:items].each { |item| nav_item(item) }
      end
    end

    def nav_item(item)
      active = @active == item[:key]
      path   = (send(item[:path]) rescue "#")
      base   = active ? NAV_ITEM_ON : NAV_ITEM
      # sidebar-nav-item enables CSS targeting for collapsed centering + tooltip
      cls    = "#{base} sidebar-nav-item"

      a(href: path, class: cls, data: { nav_tooltip: item[:label] }) do
        span(class: active ? "#{NAV_ICON_ON} flex-shrink-0" : "#{NAV_ICON_OFF} flex-shrink-0") do
          render UI::Icon.new(item[:icon], class: ICON_NAV)
        end
        span(class: "sidebar-nav-label") { item[:label] }
      end
    end

    # ── Merchant tier card ──────────────────────────────────────────────────────

    def show_tier_card?
      Current.user&.merchant_user?
    rescue
      false
    end

    def tier_card
      user = Current.user
      tier = user.merchant_tier rescue 1
      cfg  = tier_config(tier)

      div(class: "sidebar-tier-card",
          style: "margin:0 10px 10px;border-radius:12px;padding:12px 14px;" \
                 "background:#{cfg[:bg]};border:1px solid #{cfg[:border]};flex-shrink:0") do
        div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:8px") do
          div(style: "display:flex;align-items:center;gap:6px") do
            span(style: "display:flex;width:13px;height:13px;color:#{cfg[:icon_color]}") do
              render UI::Icon.new(cfg[:icon], class: "w-full h-full")
            end
            span(style: "font-size:10px;font-weight:700;letter-spacing:0.1em;text-transform:uppercase;" \
                        "color:#{cfg[:label_color]}") { plain t("tier.label") }
          end
          span(style: "font-size:10px;font-weight:700;padding:2px 7px;border-radius:20px;" \
                      "background:#{cfg[:badge_bg]};color:#{cfg[:badge_text]}") do
            plain "Tier #{tier}"
          end
        end

        p(style: "font-size:11.5px;font-weight:600;color:#{cfg[:title_color]};margin-bottom:3px") do
          plain cfg[:title]
        end
        p(style: "font-size:11px;color:#{cfg[:limit_color]};margin-bottom:#{tier < 3 ? '10px' : '0'}") do
          plain t("tier.limits.tier_#{tier}")
        end

        if tier < 3
          a(href: kyb_reviews_path,
            style: "display:flex;align-items:center;gap:5px;font-size:11.5px;font-weight:600;" \
                   "color:#{cfg[:cta_color]};text-decoration:none") do
            plain t("tier.upgrade_cta")
            span(style: "display:flex;width:11px;height:11px") do
              render UI::Icon.new(:arrow_right, class: "w-full h-full")
            end
          end
        end
      end
    end

    def tier_config(tier)
      case tier
      when 3
        {
          bg: "rgba(22,163,74,0.06)",    border: "rgba(22,163,74,0.15)",
          icon: :check_circle,           icon_color: "#16a34a",
          label_color: "#15803d",        title_color: "#15803d",
          title: t("tier.tier_3"),       limit_color: "#16a34a",
          badge_bg: "rgba(22,163,74,0.12)", badge_text: "#15803d",
          cta_color: "#16a34a"
        }
      when 2
        {
          bg: "rgba(61,71,245,0.05)",    border: "rgba(61,71,245,0.12)",
          icon: :clock,                  icon_color: "#3D47F5",
          label_color: "#3730a3",        title_color: "#3730a3",
          title: t("tier.tier_2"),       limit_color: "#6366f1",
          badge_bg: "rgba(61,71,245,0.10)", badge_text: "#3D47F5",
          cta_color: "#3D47F5"
        }
      else
        {
          bg: "rgba(217,119,6,0.06)",    border: "rgba(217,119,6,0.15)",
          icon: :alert_circle,           icon_color: "#d97706",
          label_color: "#92400e",        title_color: "#92400e",
          title: t("tier.tier_1"),       limit_color: "#b45309",
          badge_bg: "rgba(217,119,6,0.12)", badge_text: "#b45309",
          cta_color: "#d97706"
        }
      end
    end

    # ── Mode toggle ─────────────────────────────────────────────────────────────

    def show_mode_toggle?
      Current.user&.merchant_user?
    rescue
      false
    end

    def mode_toggle
      live   = Current.mode == "live"
      label  = live ? "LIVE" : "TEST"
      target = live ? "test" : "live"
      bg     = live ? "rgba(22,163,74,0.10)" : "rgba(245,158,11,0.10)"
      border = live ? "rgba(22,163,74,0.25)" : "rgba(245,158,11,0.25)"
      color  = live ? "#15803d" : "#92400e"
      dot    = live ? "#16a34a" : "#d97706"

      div(style: "margin:0 10px 8px;flex-shrink:0") do
        form(action: portal_mode_path, method: :post,
             data: { turbo: false }) do
          input(type: "hidden", name: "_method",                value: "post")
          input(type: "hidden", name: "authenticity_token",     value: form_authenticity_token)
          input(type: "hidden", name: "mode",                   value: target)

          button(type: "submit",
                 title: "Switch to #{target} mode",
                 style: "width:100%;display:flex;align-items:center;justify-content:space-between;" \
                        "padding:7px 10px;border-radius:9px;border:1px solid #{border};" \
                        "background:#{bg};cursor:pointer;gap:8px") do
            div(style: "display:flex;align-items:center;gap:6px") do
              span(style: "width:7px;height:7px;border-radius:50%;background:#{dot};flex-shrink:0")
              span(class: "sidebar-nav-label",
                   style: "font-size:11px;font-weight:700;letter-spacing:0.08em;color:#{color}") { label }
            end
            span(class: "sidebar-nav-label",
                 style: "font-size:10px;color:#{color};opacity:0.7") { "Switch" }
          end
        end
      end
    end

    # ── User row ────────────────────────────────────────────────────────────────

    def user_row
      user = Current.user
      return unless user

      div(style: "display:flex;align-items:center;gap:10px;padding:12px 16px;" \
                 "border-top:1px solid #{BORDER};flex-shrink:0;overflow:hidden") do
        render UI::Avatar.new(initials(user), size: :md)
        div(class: "sidebar-nav-label", style: "min-width:0;overflow:hidden") do
          p(style: "font-size:12.5px;font-weight:600;color:#{INK};white-space:nowrap;" \
                   "overflow:hidden;text-overflow:ellipsis") { plain user.full_name }
          p(style: "font-size:11px;color:#{MUTED_TEXT};white-space:nowrap;" \
                   "overflow:hidden;text-overflow:ellipsis") { plain user.email }
        end
      end
    end

    def initials(user)
      user.full_name.split.map { |w| w[0] }.first(2).join.upcase
    end

    def internal_staff?
      Current.user&.internal_staff?
    rescue
      false
    end
  end
end
