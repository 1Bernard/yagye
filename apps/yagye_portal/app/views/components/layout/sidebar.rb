# frozen_string_literal: true

module Layout
  class Sidebar < ApplicationComponent
    include UI::Theme

    NAV_SECTIONS = [
      {
        label: nil,
        items: [
          { key: :dashboard,     icon: :home,        label: "Dashboard",     path: :authenticated_root_path },
          { key: :payments,      icon: :credit_card, label: "Payments",      path: :payments_path },
          { key: :disputes,      icon: :flag,        label: "Disputes",      path: :disputes_path },
          { key: :payouts,       icon: :paper_plane, label: "Payouts",       path: :payouts_path,
            merchant_only: true },
          { key: :payment_links,     icon: :link,        label: "Payment Links",     path: :payment_links_path,
            merchant_only: true },
          { key: :invoices,          icon: :file,        label: "Invoices",          path: :invoices_path,
            merchant_only: true },
          { key: :checkout_sessions, icon: :wallet,      label: "Checkout Sessions", path: :checkout_sessions_path,
            merchant_only: true },
          { key: :customers,         icon: :users,       label: "Customers",         path: :customers_path,
            merchant_only: true },
          { key: :settlement_batches, icon: :layers,     label: "Settlement Batches", path: :settlement_batches_path,
            merchant_only: true },
          { key: :reserves,          icon: :lock,        label: "Reserves",          path: :reserves_path,
            merchant_only: true }
        ]
      },
      {
        label: "TEAM",
        items: [
          { key: :team_users,        icon: :users,  label: "Users",             path: :team_users_path },
          { key: :team_role_requests, icon: :clock,  label: "Role Requests",     path: :team_role_requests_path,
            internal_only: true },
          { key: :team_roles,        icon: :shield, label: "Roles & Permissions", path: :team_roles_path }
        ]
      },
      {
        label: "OPERATIONS",
        internal_only: true,
        items: [
          { key: :merchants,       icon: :building,     label: "Merchants",       path: :merchants_path },
          { key: :kyb_reviews,     icon: :shield,       label: "KYB Review",      path: :kyb_reviews_path },
          { key: :approvals,       icon: :check_circle, label: "Approvals",       path: :compliance_approvals_path },
          { key: :routing_rules,   icon: :swap,         label: "Routing Rules",   path: :developers_routing_rules_path },
          { key: :reconciliation,  icon: :trending_up,  label: "Reconciliation",  path: :reconciliation_path },
          { key: :settlements,     icon: :wallet,       label: "Settlements",      path: :settlements_path }
        ]
      },
      {
        label: "ACCOUNT",
        items: [
          { key: :developers, icon: :key,      label: "API Keys",       path: :developers_path },
          { key: :settings,   icon: :settings, label: "Settings",       path: :settings_path },
          { key: :settings_pricing, icon: :tag, label: "Pricing & Fees", path: :settings_pricing_path,
            merchant_only: true },
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

      div(class: "px-3 mb-1") do
        if section[:label]
          p(class: "sidebar-section-label #{SIDEBAR_LABEL}") { plain section[:label] }
        end
        section[:items].each { |item| nav_item(item) }
      end
    end

    def nav_item(item)
      return if item[:internal_only] && !internal_staff?
      return if item[:merchant_only] && internal_staff?

      active = @active == item[:key]
      path   = (send(item[:path]) rescue "#")
      base   = active ? NAV_ITEM_ON : NAV_ITEM
      # sidebar-nav-item enables CSS targeting for collapsed centering + tooltip
      cls    = "#{base} sidebar-nav-item"

      a(href: path, class: cls, data: { nav_tooltip: item[:label] }) do
        span(class: active ? NAV_ICON_ON : "#{NAV_ICON_OFF} flex-shrink-0") do
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
      user     = Current.user
      tier     = user.merchant_tier rescue 1
      cfg      = tier_config(tier)
      done_pct = tier == 3 ? 100 : tier == 2 ? 60 : 15
      deg      = (done_pct * 3.6).round(1)


      div(class: "sidebar-tier-card",
          style: "margin:0 10px 6px;border-radius:12px;padding:12px 13px;" \
                 "background:#{cfg[:bg]};border:1px solid #{cfg[:border]};flex-shrink:0") do

        # Top row: conic ring + title + badge
        div(style: "display:flex;align-items:center;gap:9px;margin-bottom:9px") do
          # Conic ring — compact version of the settings verification banner ring
          div(style: "width:28px;height:28px;border-radius:50%;flex-shrink:0;" \
                     "display:flex;align-items:center;justify-content:center;padding:3px;" \
                     "background:conic-gradient(#{cfg[:accent]} #{deg}deg, rgba(128,128,128,0.15) #{deg}deg)") do
            div(style: "width:100%;height:100%;border-radius:50%;background:white;" \
                       "display:flex;align-items:center;justify-content:center") do
              span(style: "font-size:8.5px;font-weight:800;color:#{cfg[:accent]};line-height:1") do
                plain "T#{tier}"
              end
            end
          end

          div(style: "flex:1;min-width:0") do
            div(style: "display:flex;align-items:center;justify-content:space-between;gap:4px") do
              p(style: "font-size:11.5px;font-weight:700;color:#{cfg[:title_color]};line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis") do
                plain cfg[:title]
              end
              span(class: "sidebar-nav-label",
                   style: "font-size:9px;font-weight:700;padding:2px 6px;border-radius:20px;letter-spacing:0.03em;flex-shrink:0;" \
                          "background:#{cfg[:badge_bg]};color:#{cfg[:accent]}") do
                plain "Tier #{tier}"
              end
            end
          end
        end

        # Limit
        p(class: "sidebar-nav-label",
          style: "font-size:11px;font-weight:500;color:#{cfg[:limit_color]};" \
                 "margin-bottom:#{tier < 3 ? '9px' : '0'};line-height:1.3") do
          plain t("tier.limits.tier_#{tier}")
        end

        # CTA
        if tier < 3
          div(style: "height:1px;background:#{cfg[:divider]};margin-bottom:8px")
          a(href: settings_path(tab: "verification"),
            style: "display:flex;align-items:center;justify-content:space-between;text-decoration:none") do
            span(class: "sidebar-nav-label",
                 style: "font-size:11px;font-weight:600;color:#{cfg[:cta_color]}") do
              plain t("tier.upgrade_cta")
            end
            span(style: "display:flex;width:11px;height:11px;color:#{cfg[:cta_color]};flex-shrink:0") do
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
          accent: "#16a34a",
          bg: "rgba(22,163,74,0.05)",     border: "rgba(22,163,74,0.14)",
          glow: "rgba(22,163,74,0.18)",   muted_border: "rgba(22,163,74,0.25)",
          title_color: "#15803d",         limit_color: "#16a34a",
          badge_bg: "rgba(22,163,74,0.12)", cta_color: "#16a34a",
          divider: "rgba(22,163,74,0.10)",
          title: t("tier.tier_3"),
          icon: :check_circle,            icon_color: "#16a34a",
          label_color: "#15803d",         badge_text: "#15803d"
        }
      when 2
        {
          accent: "#3D47F5",
          bg: "rgba(61,71,245,0.05)",     border: "rgba(61,71,245,0.12)",
          glow: "rgba(61,71,245,0.18)",   muted_border: "rgba(61,71,245,0.20)",
          title_color: "#3730a3",         limit_color: "#6366f1",
          badge_bg: "rgba(61,71,245,0.10)", cta_color: "#3D47F5",
          divider: "rgba(61,71,245,0.10)",
          title: t("tier.tier_2"),
          icon: :clock,                   icon_color: "#3D47F5",
          label_color: "#3730a3",         badge_text: "#3D47F5"
        }
      else
        {
          accent: "#d97706",
          bg: "rgba(217,119,6,0.05)",     border: "rgba(217,119,6,0.14)",
          glow: "rgba(217,119,6,0.18)",   muted_border: "rgba(217,119,6,0.22)",
          title_color: "#92400e",         limit_color: "#b45309",
          badge_bg: "rgba(217,119,6,0.12)", cta_color: "#d97706",
          divider: "rgba(217,119,6,0.10)",
          title: t("tier.tier_1"),
          icon: :alert_circle,            icon_color: "#d97706",
          label_color: "#92400e",         badge_text: "#b45309"
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
      live    = Current.mode == "live"
      enabled = live_mode_enabled?

      # Switching back to test is always allowed; switching to live requires enablement.
      if !live && !enabled
        mode_toggle_locked
      else
        mode_toggle_active(live)
      end
    end

    def mode_toggle_active(live)
      label  = live ? "LIVE" : "TEST"
      target = live ? "test" : "live"
      dot    = live ? "#16a34a" : "#d97706"
      color  = live ? "#15803d" : "#92400e"
      bg     = live ? "rgba(22,163,74,0.07)" : "rgba(245,158,11,0.07)"
      border = live ? "rgba(22,163,74,0.20)" : "rgba(245,158,11,0.20)"
      hint   = live ? "Switch to test" : "Switch to live"

      div(style: "margin:0 10px 8px;flex-shrink:0") do
        form(action: portal_mode_path, method: :post, data: { turbo: false }) do
          input(type: "hidden", name: "_method",            value: "post")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "mode",               value: target)

          button(type: "submit",
                 title: hint,
                 style: "width:100%;display:flex;align-items:center;justify-content:space-between;" \
                        "padding:6px 10px 6px 11px;border-radius:9px;border:1px solid #{border};" \
                        "background:#{bg};cursor:pointer;gap:8px") do
            div(style: "display:flex;align-items:center;gap:7px") do
              span(style: "width:6px;height:6px;border-radius:50%;background:#{dot};flex-shrink:0;" \
                          "#{"box-shadow:0 0 0 2.5px rgba(22,163,74,0.20)" if live}")
              span(class: "sidebar-nav-label",
                   style: "font-size:10.5px;font-weight:700;letter-spacing:0.09em;color:#{color}") { plain label }
            end
            div(class: "sidebar-nav-label",
                style: "display:flex;align-items:center;gap:3px") do
              span(style: "font-size:10px;color:#{color};opacity:0.6") { plain hint }
              span(style: "display:flex;width:9px;height:9px;color:#{color};opacity:0.5;flex-shrink:0") do
                render UI::Icon.new(:arrow_right, class: "w-full h-full")
              end
            end
          end
        end
      end
    end

    def mode_toggle_locked
      div(style: "margin:0 10px 8px;flex-shrink:0") do
        a(href: settings_path(tab: "verification"),
          style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:6px 10px 6px 11px;border-radius:9px;" \
                 "border:1px solid rgba(245,158,11,0.18);" \
                 "background:rgba(245,158,11,0.06);text-decoration:none;gap:8px") do
          div(style: "display:flex;align-items:center;gap:7px") do
            span(style: "width:6px;height:6px;border-radius:50%;background:#d97706;flex-shrink:0")
            span(class: "sidebar-nav-label",
                 style: "font-size:10.5px;font-weight:700;letter-spacing:0.09em;color:#92400e") { plain "TEST" }
          end
          div(class: "sidebar-nav-label",
              style: "display:flex;align-items:center;gap:3px") do
            span(style: "font-size:10px;color:#b45309;opacity:0.7") { plain "Go live" }
            span(style: "display:flex;width:9px;height:9px;color:#b45309;opacity:0.5;flex-shrink:0") do
              render UI::Icon.new(:arrow_right, class: "w-full h-full")
            end
          end
        end
      end
    end

    def live_mode_enabled?
      return false unless Current.user&.merchant_user?
      PortalMerchant.find_for(Current.user.merchant_code)&.live_mode_enabled? || false
    rescue
      false
    end

    # ── User row ────────────────────────────────────────────────────────────────

    def user_row
      user = Current.user
      return unless user

      div(style: "display:flex;align-items:center;gap:10px;padding:12px 16px;" \
                 "border-top:1px solid #{BORDER};flex-shrink:0;overflow:hidden") do
        render UI::Avatar.new(initials(user), size: :md)
        div(class: "sidebar-nav-label",
            style: "display:flex;flex-direction:column;gap:1px;min-width:0;overflow:hidden") do
          p(style: "font-size:12.5px;font-weight:600;color:#{INK};white-space:nowrap;line-height:1.2;" \
                   "overflow:hidden;text-overflow:ellipsis") { plain user.full_name }
          p(style: "font-size:11px;color:#{MUTED_TEXT};white-space:nowrap;line-height:1.2;" \
                   "overflow:hidden;text-overflow:ellipsis") { plain sidebar_role_label(user) }
        end
      end
    end

    def initials(user)
      user.full_name.split.map { |w| w[0] }.first(2).join.upcase
    end

    def sidebar_role_label(user)
      return "Yagye Staff" if user.internal_staff?
      user.roles.first&.name&.tr("_", " ")&.split&.map(&:capitalize)&.join(" ") || "Merchant"
    end

    def internal_staff?
      Current.user&.internal_staff?
    rescue
      false
    end
  end
end
