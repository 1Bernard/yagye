# frozen_string_literal: true

module Layout
  # Premium topbar — left side is a single breadcrumb trail where the LAST
  # crumb renders as the page title (display weight/size). No separate h1.
  # Right side: notifications · user menu. Language and theme live in Settings.
  class Topbar < ApplicationComponent
    include UI::Theme

    DISPLAY  = "font-family:'Plus Jakarta Sans',sans-serif;font-size:16px;font-weight:700;" \
               "color:#{INK};letter-spacing:-0.025em;line-height:1"
    ANCESTOR = "font-size:12px;font-weight:500;color:#{MUTED_TEXT};text-decoration:none;white-space:nowrap;" \
               "transition:color 140ms"
    SEP      = "margin:0 7px;color:#{FAINT_TEXT};font-size:11px;user-select:none;line-height:1"
    HOME_ICON_CLR = FAINT_TEXT

    def initialize(title:, subtitle: nil, breadcrumbs: nil)
      @title       = title
      @breadcrumbs = breadcrumbs
    end

    def view_template
      header(style: "background:#{CARD_BG};border-bottom:1px solid #{BORDER};position:sticky;top:0;z-index:10") do
        div(style: "display:flex;align-items:center;justify-content:space-between;" \
                   "padding:0 24px;height:56px") do
          left_block
          right_actions
        end
      end
    end

    private

    # ── Left: breadcrumb trail ────────────────────────────────────────────────

    def left_block
      nav(aria: { label: "Breadcrumb" }) do
        ol(style: "display:flex;align-items:center;list-style:none;padding:0;margin:0;gap:0") do
          home_crumb

          if @breadcrumbs&.any?
            @breadcrumbs.each_with_index do |item, idx|
              last = (idx == @breadcrumbs.length - 1)
              separator_crumb
              if last
                li(style: "display:flex;align-items:center") do
                  span(style: DISPLAY) { plain item[:label] }
                end
              elsif item[:href]
                li(style: "display:flex;align-items:center") do
                  a(href: item[:href], style: ANCESTOR, class: "topbar-ancestor-crumb") do
                    plain item[:label]
                  end
                end
              else
                li(style: "display:flex;align-items:center") do
                  span(style: "#{ANCESTOR};pointer-events:none") { plain item[:label] }
                end
              end
            end
          else
            separator_crumb
            li(style: "display:flex;align-items:center") do
              span(style: DISPLAY) { plain @title }
            end
          end
        end
      end
    end

    def home_crumb
      li(style: "display:flex;align-items:center;flex-shrink:0") do
        a(href: authenticated_root_path,
          style: "display:flex;align-items:center;color:#{HOME_ICON_CLR};transition:color 140ms",
          class: "topbar-home-crumb",
          title: "Home") do
          span(style: "display:flex;width:13px;height:13px") do
            render UI::Icon.new(:home, class: "w-full h-full")
          end
        end
      end
    end

    def separator_crumb
      li(style: "display:flex;align-items:center;flex-shrink:0") do
        span(style: SEP) { "/" }
      end
    end

    # ── Right: notifications · user menu ─────────────────────────────────────

    def right_actions
      div(style: "display:flex;align-items:center;gap:2px;flex-shrink:0") do
        notif_btn
        user_menu
      end
    end

    def notif_btn
      button(type: "button",
             class: "topbar-icon-btn",
             style: "width:34px;height:34px;border-radius:7px;display:flex;align-items:center;" \
                    "justify-content:center;color:#{MUTED_TEXT}",
             title: "Notifications") do
        span(style: "display:flex;width:16px;height:16px") do
          render UI::Icon.new(:bell, class: "w-full h-full")
        end
      end
    end

    def user_menu
      user = Current.user
      return unless user

      div(style: "position:relative", data: { controller: "dropdown" }) do
        button(type: "button",
               class: "topbar-user-btn",
               data:  { action: "click->dropdown#toggle" }) do
          render UI::Avatar.new(user_initials(user), size: :sm)
          div(style: "display:flex;flex-direction:column;gap:1px;text-align:left;min-width:0") do
            p(style: "font-size:13px;font-weight:600;color:#{INK};white-space:nowrap;line-height:1.2") do
              plain user.full_name
            end
            p(style: "font-size:11px;font-weight:400;color:#{MUTED_TEXT};white-space:nowrap;line-height:1.2") do
              plain role_label(user)
            end
          end
          span(style: "display:flex;width:12px;height:12px;color:#{SUBTLE_TEXT};flex-shrink:0") do
            render UI::Icon.new(:chev, class: "w-full h-full")
          end
        end

        div(class: "right-0 top-full mt-1 #{DROPDOWN_MENU}",
            style: "min-width:224px;border-radius:14px;padding:5px;background:#{CARD_BG};" \
                   "box-shadow:0 8px 30px rgba(0,0,0,0.10),0 2px 8px rgba(0,0,0,0.06)",
            data: { dropdown_target: "menu" }) do
          user_header(user)
          div(style: "height:1px;background:#{SURFACE};margin:4px 8px")
          menu_item(:user,     t("topbar.profile"), "#")
          menu_item(:settings, t("nav.settings"),   settings_path)
          div(style: "height:1px;background:#{SURFACE};margin:4px 8px")
          sign_out_item
        end
      end
    end

    def user_header(user)
      div(style: "padding:10px 12px 8px") do
        p(style: "font-size:13px;font-weight:600;color:#{INK}") { plain user.full_name }
        p(style: "font-size:11.5px;color:#{MUTED_TEXT};margin-top:2px;" \
                 "overflow:hidden;text-overflow:ellipsis;white-space:nowrap") do
          plain user.email
        end
      end
    end

    def menu_item(icon, label, href)
      a(href: href, class: "topbar-menu-item") do
        span(style: "display:flex;width:14px;height:14px;color:#{SUBTLE_TEXT}") do
          render UI::Icon.new(icon, class: "w-full h-full")
        end
        plain label
      end
    end

    def sign_out_item
      a(href: destroy_user_session_path,
        data: { turbo_method: :delete },
        class: "topbar-menu-item topbar-menu-item--danger") do
        span(style: "display:flex;width:14px;height:14px") do
          render UI::Icon.new(:logout, class: "w-full h-full")
        end
        plain t("topbar.sign_out")
      end
    end

    def user_initials(user)
      user.full_name.split.map { |w| w[0] }.first(2).join.upcase
    end

    def role_label(user)
      return "Yagye Staff" if user.internal_staff?
      user.roles.first&.name&.tr("_", " ")&.split&.map(&:capitalize)&.join(" ") || "Merchant"
    end
  end
end
