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
      header(style: "background:#{CARD_BG};border-bottom:1px solid #{BORDER};position:sticky;top:0;z-index:20") do
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
      return unless current_user

      unread   = PortalNotification.for_user(current_user).unread.count
      recent   = PortalNotification.for_user(current_user).recent.limit(12)

      div(style: "position:relative", data: { controller: "dropdown" }) do
        button(type: "button",
               class: "topbar-icon-btn",
               style: "position:relative;width:34px;height:34px;border-radius:7px;display:flex;" \
                      "align-items:center;justify-content:center;color:#{MUTED_TEXT}",
               title: "Notifications",
               data:  { action: "click->dropdown#toggle" }) do
          span(style: "display:flex;width:16px;height:16px") do
            render UI::Icon.new(:bell, class: "w-full h-full")
          end
          # Badge — this element is replaced via broadcast_replace_to
          span(id: "notif-bell", style: "position:absolute;top:-2px;right:-2px;pointer-events:none;") do
            if unread > 0
              span(style: "display:flex;align-items:center;justify-content:center;" \
                          "min-width:16px;height:16px;padding:0 3px;border-radius:8px;" \
                          "background:#EF4444;font-size:9px;font-weight:700;color:#fff;" \
                          "line-height:1;border:1.5px solid #fff;") do
                plain unread > 99 ? "99+" : unread.to_s
              end
            end
          end
        end

        div(class: "right-0 top-full mt-1 #{DROPDOWN_MENU}",
            style: "width:320px;border-radius:14px;background:#{CARD_BG};" \
                   "box-shadow:0 8px 30px rgba(0,0,0,0.10),0 2px 8px rgba(0,0,0,0.06);" \
                   "overflow:hidden;",
            data: { dropdown_target: "menu" }) do
          notif_dropdown_header(unread)
          div(id: "notif-list", style: "max-height:320px;overflow-y:auto;") do
            if recent.any?
              recent.each { |n| notif_row(n) }
            else
              notif_empty_state
            end
          end
        end
      end
    end

    def notif_dropdown_header(unread)
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:12px 16px 10px;border-bottom:1px solid #{BORDER};") do
        span(style: "font-size:13px;font-weight:700;color:#{INK};") { plain "Notifications" }
        if unread > 0
          form(action: notifications_read_all_path, method: "post",
               data: { turbo: true }) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: authenticity_token_field, value: form_authenticity_token)
            button(type: "submit",
                   style: "font-size:11.5px;font-weight:500;color:#{BRAND};background:none;" \
                          "border:none;cursor:pointer;padding:0;") do

              plain "Mark all read"
            end
          end
        end
      end
    end

    def notif_row(notif)
      div(style: "border-bottom:1px solid #f3f4f6;") do
        a(href: notification_open_path(notif),
          style: "display:flex;gap:10px;padding:12px 16px;text-decoration:none;" \
                 "background:#{notif.read? ? '#fff' : '#F5F6FF'};" \
                 "transition:background 120ms;") do
          div(style: "flex-shrink:0;margin-top:6px;") do
            span(style: "display:block;width:7px;height:7px;border-radius:50%;" \
                        "background:#{notif.read? ? '#d1d5db' : BRAND};") {}
          end
          div(style: "flex:1;min-width:0;") do
            p(style: "font-size:12.5px;font-weight:600;color:#{INK};margin:0 0 2px;" \
                     "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;") do
              plain notif.title
            end
            p(style: "font-size:11.5px;color:#{MUTED_TEXT};margin:0;line-height:1.4;") do
              plain notif.body.truncate(80)
            end
            p(style: "font-size:10.5px;color:#{FAINT_TEXT};margin:4px 0 0;") do
              plain notif.created_at.strftime("%-d %b, %H:%M")
            end
          end
        end
      end
    end

    def notif_empty_state
      div(style: "padding:32px 16px;text-align:center;") do
        span(style: "display:flex;width:28px;height:28px;margin:0 auto 10px;color:#{FAINT_TEXT};") do
          render UI::Icon.new(:bell, class: "w-full h-full")
        end
        p(style: "font-size:12.5px;color:#{MUTED_TEXT};") { plain "No notifications yet" }
      end
    end

    def authenticity_token_field
      "authenticity_token"
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
