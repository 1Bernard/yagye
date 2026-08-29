# frozen_string_literal: true

module Team
  module Users
    class IndexPage < ApplicationComponent
      include UI::Theme

      def initialize(users: [], can_invite: false, query: nil, role: nil, status: nil)
        @users      = users
        @can_invite = can_invite
        @query      = query
        @role       = role
        @status     = status
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_users,
          title:      "Team members",
          breadcrumbs: [
            { label: "Team" },
            { label: "Users" }
          ]
        ) do
          page_header
          stat_band
          users_table
        end
      end

      private

      def page_header
        div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:20px") do
          div do
            p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Team" }
            h1(style: TYPE_DISPLAY) { "Team members" }
          end
          if @can_invite
            button(type: "button", class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              "Invite member"
            end
          end
        end
      end

      def stat_band
        total   = @users.size
        active  = @users.count { |u| u.kind == "merchant_user" || u.kind == "internal_staff" }
        pending = 0

        div(style: "display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px") do
          stat_cell("Total members",  total.to_s,   icon: :users,        color: "#3D47F5", tint: "rgba(61,71,245,0.08)")
          stat_cell("Active",         active.to_s,  icon: :check_circle, color: "#16a34a", tint: "rgba(22,163,74,0.08)")
          stat_cell("Pending invite", pending.to_s, icon: :clock,        color: "#d97706", tint: "rgba(217,119,6,0.08)")
          stat_cell("Roles defined",  "8",          icon: :key,          color: "#6d28d9", tint: "rgba(109,40,217,0.08)")
        end
      end

      def users_table
        can_invite = @can_invite
        query      = @query
        role       = @role
        status     = @status
        total      = @users.size

        render UI::Datatable.new(records: @users,
                                 empty_message: "No team members found. Invite someone to get started.") do |t|
          t.header do
            div(style: "display:flex;align-items:center;gap:8px") do
              p(style: TYPE_TITLE) { "All members" }
              span(style: "background:#f3f4f6;color:#6b7280;border-radius:20px;" \
                          "padding:1px 9px;font-size:11.5px;font-weight:600;line-height:1.6") { total.to_s } if total > 0
            end

            form(action: team_users_path, method: "get",
                 style: "display:flex;align-items:center;gap:6px") do
              div(style: "display:flex;align-items:center;gap:7px;padding:0 11px;" \
                         "border:1px solid #e5e7eb;border-radius:9px;background:#fff;height:32px") do
                span(style: "display:flex;width:12px;height:12px;color:#9ca3af;flex-shrink:0") do
                  render UI::Icon.new(:search, class: "w-full h-full")
                end
                input(type: "search", name: "q", value: query,
                      placeholder: "Search by name or email…",
                      style: "border:0;outline:none;background:transparent;font-size:12.5px;" \
                             "color:#374151;width:170px;min-width:0",
                      class: "placeholder:text-gray-400")
              end

              select(name: "role",
                     style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                            "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                            "outline:none;cursor:pointer;height:32px") do
                option(value: "", selected: role.blank?) { "All roles" }
                [["Owner","merchant_owner"],["Finance","merchant_finance"],
                 ["Developer","merchant_developer"],["Support","merchant_support"],
                 ["Ops Analyst","ops_analyst"],["Ops Manager","ops_manager"],
                 ["Compliance Analyst","compliance_analyst"],["Compliance Manager","compliance_manager"]].each do |(lbl, val)|
                  option(value: val, selected: role == val) { lbl }
                end
              end

              select(name: "status",
                     style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                            "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                            "outline:none;cursor:pointer;height:32px") do
                option(value: "", selected: status.blank?) { "All" }
                option(value: "active",    selected: status == "active") { "Active" }
                option(value: "suspended", selected: status == "suspended") { "Suspended" }
              end

              button(type: "submit",
                     style: "display:inline-flex;align-items:center;padding:0 12px;" \
                            "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                            "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                            "height:32px;white-space:nowrap") { plain "Filter" }

              if query.present? || role.present? || status.present?
                a(href: team_users_path,
                  style: "font-size:12px;color:#9ca3af;text-decoration:none;" \
                         "padding:0 4px;white-space:nowrap") { "Clear" }
              end
            end
          end

          t.column("Member") do |u|
            initials = u.full_name.split.map { |w| w[0] }.first(2).join.upcase
            div(style: "display:flex;align-items:center;gap:10px") do
              render UI::Avatar.new(initials, size: :sm)
              div do
                p(style: TYPE_BODY_MD) { u.full_name }
                p(style: TYPE_CAPTION) { u.email }
              end
            end
          end

          t.column("Role") do |u|
            roles = u.roles
            if roles.empty?
              span(style: TYPE_CAPTION) { "No role" }
            else
              div(style: "display:flex;flex-wrap:wrap;gap:4px") do
                roles.first(2).each do |role_obj|
                  bg = role_obj.scope == "internal" ? "#dbeafe" : "#f3f4f6"
                  fg = role_obj.scope == "internal" ? "#1d4ed8" : MUTED_TEXT
                  span(style: "font-size:11px;font-weight:600;padding:2px 8px;border-radius:20px;" \
                              "background:#{bg};color:#{fg}") { role_obj.name }
                end
                span(style: "font-size:11px;color:#{MUTED_TEXT}") { "+#{roles.size - 2}" } if roles.size > 2
              end
            end
          end

          t.column("Type") do |u|
            if u.kind == "internal_staff"
              span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:20px;" \
                          "background:#dbeafe;color:#1d4ed8") { "Staff" }
            else
              span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:20px;" \
                          "background:#f3f4f6;color:#{MUTED_TEXT}") { "Merchant" }
            end
          end

          t.column("Last active") do |u|
            ts = u.last_sign_in_at
            span(style: TYPE_CAPTION) { ts ? ts.strftime("%d %b %Y") : "Never" }
          end

          t.column("Joined") { |u| u.created_at.strftime("%d %b %Y") }

          t.actions do |u|
            a(href: team_user_path(u), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              "View"
            end
            if can_invite
              div(class: DROPDOWN_SEP)
              button(type: "button", class: DROPDOWN_ITEM_DANGER) do
                render UI::Icon.new(:archive, class: ICON_SM)
                "Suspend"
              end
            end
          end
        end
      end
    end
  end
end
