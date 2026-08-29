# frozen_string_literal: true

module Team
  module Users
    class IndexPage < ApplicationComponent
      include UI::Theme

      def initialize(users: [], can_invite: false)
        @users      = users
        @can_invite = can_invite
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
          filter_bar_section
          users_table
        end
      end

      private

      def page_header
        div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:24px") do
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

        div(class: "#{STAT_BAND} mb-6") do
          stat_cell("Total members",   total.to_s)
          stat_cell("Active",          active.to_s,  color: "#16a34a")
          stat_cell("Pending invite",  pending.to_s, color: "#f59e0b")
          stat_cell("Roles defined",   "8")
        end
      end

      def stat_cell(label, value, color: INK)
        div(class: STAT_CELL) do
          p(style: TYPE_MICRO) { label }
          p(style: "font-size:28px;font-weight:700;color:#{color};font-variant-numeric:tabular-nums;" \
                    "line-height:1;margin-top:6px") { value }
        end
      end

      def filter_bar_section
        render UI::FilterBar.new(action: team_users_path) do |f|
          f.search_field name: "q", value: nil, placeholder: "Search by name or email..."
          f.select_field name: "role", label: "Role",
                         options: [
                           [ "All roles",           "" ],
                           [ "Owner",               "merchant_owner" ],
                           [ "Finance",             "merchant_finance" ],
                           [ "Developer",           "merchant_developer" ],
                           [ "Support",             "merchant_support" ],
                           [ "Ops Analyst",         "ops_analyst" ],
                           [ "Ops Manager",         "ops_manager" ],
                           [ "Compliance Analyst",  "compliance_analyst" ],
                           [ "Compliance Manager",  "compliance_manager" ]
                         ]
          f.select_field name: "status", label: "Status",
                         options: [ [ "All", "" ], [ "Active", "active" ], [ "Suspended", "suspended" ] ]
        end
      end

      def users_table
        render UI::Datatable.new(records: @users,
                                 empty_message: "No team members found. Invite someone to get started.") do |t|
          t.header do
            p(style: TYPE_TITLE) { "All members" }
          end

          t.column("Member")       { |u| member_cell(u) }
          t.column("Role")         { |u| roles_cell(u) }
          t.column("Type")         { |u| kind_badge(u.kind) }
          t.column("Last active")  { |u| last_active(u) }
          t.column("Joined")       { |u| u.created_at.strftime("%d %b %Y") }

          t.actions do |u|
            a(href: team_user_path(u), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              "View"
            end
            if @can_invite
              div(class: DROPDOWN_SEP)
              button(type: "button", class: DROPDOWN_ITEM_DANGER) do
                render UI::Icon.new(:archive, class: ICON_SM)
                "Suspend"
              end
            end
          end
        end
      end

      def member_cell(user)
        div(style: "display:flex;align-items:center;gap:10px") do
          render UI::Avatar.new(initials(user), size: :sm)
          div do
            p(style: TYPE_BODY_MD) { user.full_name }
            p(style: TYPE_CAPTION) { user.email }
          end
        end
      end

      def roles_cell(user)
        roles = user.roles
        if roles.empty?
          span(style: TYPE_CAPTION) { "No role" }
        else
          div(style: "display:flex;flex-wrap:wrap;gap:4px") do
            roles.first(2).each do |role|
              span(style: "font-size:11px;font-weight:600;padding:2px 8px;border-radius:20px;" \
                          "background:#{role_bg(role.scope)};color:#{role_fg(role.scope)}") do
                role.name
              end
            end
            if roles.size > 2
              span(style: "font-size:11px;color:#{MUTED_TEXT}") { "+#{roles.size - 2}" }
            end
          end
        end
      end

      def kind_badge(kind)
        if kind == "internal_staff"
          span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:20px;" \
                      "background:#dbeafe;color:#1d4ed8") { "Staff" }
        else
          span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:20px;" \
                      "background:#f3f4f6;color:#{MUTED_TEXT}") { "Merchant" }
        end
      end

      def role_bg(scope)
        scope == "internal" ? "#dbeafe" : "#f3f4f6"
      end

      def role_fg(scope)
        scope == "internal" ? "#1d4ed8" : MUTED_TEXT
      end

      def last_active(user)
        ts = user.last_sign_in_at
        return span(style: TYPE_CAPTION) { "Never" } unless ts
        span(style: TYPE_CAPTION) { ts.strftime("%d %b %Y") }
      end

      def initials(user)
        user.full_name.split.map { |w| w[0] }.first(2).join.upcase
      end
    end
  end
end
