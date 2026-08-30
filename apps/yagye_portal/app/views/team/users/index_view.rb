# frozen_string_literal: true

module Team
  module Users
    class IndexView < ApplicationComponent
      include UI::Theme

      ROLES = [
        [ "Owner",              "merchant_owner" ],
        [ "Finance",            "merchant_finance" ],
        [ "Developer",          "merchant_developer" ],
        [ "Support",            "merchant_support" ],
        [ "Ops Analyst",        "ops_analyst" ],
        [ "Ops Manager",        "ops_manager" ],
        [ "Compliance Analyst", "compliance_analyst" ],
        [ "Compliance Manager", "compliance_manager" ]
      ].freeze

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
          stat_band
          users_table
        end
      end

      private

      def stat_band
        total   = @users.size
        active  = @users.count { |u| u.kind == "merchant_user" || u.kind == "internal_staff" }
        pending = 0

        render UI::Grid.new(columns: 4) do
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
            div(class: "flex items-center gap-2") do
              p(class: TYPE_TITLE) { plain "All members" }
              if total > 0
                span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") do
                  plain total.to_s
                end
              end
            end

            div(class: "flex items-center gap-2") do
              if can_invite
                render UI::Button.new(variant: :primary,
                       data: { action: "click->dialog#open", dialog_target_param: "invite-member-dialog" }) do
                  render UI::Icon.new(:plus, class: ICON_SM)
                  plain "Invite member"
                end
                invite_dialog
              end

              form(action: team_users_path, method: "get",
                   class: "flex items-center gap-1.5",
                   data: { controller: "filter-form", filter_form_target: "form" }) do
                div(class: "flex items-center gap-2 px-[11px] border border-gray-200 rounded-[9px] bg-white h-8") do
                  span(class: "flex w-3 h-3 text-gray-400 flex-shrink-0") do
                    render UI::Icon.new(:search, class: "w-full h-full")
                  end
                  input(type: "search", name: "q", value: query,
                        placeholder: "Search by name or email…",
                        class: "border-0 outline-none bg-transparent text-[12.5px] text-gray-700 w-[170px] min-w-0 placeholder:text-gray-400")
                end

                select(name: "role",
                       class: "border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer h-8",
                       data: { action: "change->filter-form#submit" }) do
                  option(value: "", selected: role.blank?) { plain "All roles" }
                  ROLES.each do |(lbl, val)|
                    option(value: val, selected: role == val) { plain lbl }
                  end
                end

                select(name: "status",
                       class: "border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer h-8",
                       data: { action: "change->filter-form#submit" }) do
                  option(value: "", selected: status.blank?) { plain "All" }
                  option(value: "active",    selected: status == "active") { plain "Active" }
                  option(value: "suspended", selected: status == "suspended") { plain "Suspended" }
                end

                button(type: "submit",
                       class: "inline-flex items-center gap-[5px] px-3 border border-gray-200 rounded-[9px] text-[12.5px] font-medium text-gray-700 bg-white cursor-pointer h-8 whitespace-nowrap") do
                  render UI::Icon.new(:filter, class: "w-3 h-3")
                  plain "Filter"
                end

                if query.present? || role.present? || status.present?
                  a(href: team_users_path,
                    class: "text-[12px] text-gray-400 no-underline px-1 whitespace-nowrap") { plain "Clear" }
                end
              end
            end
          end

          t.column("Member") do |u|
            initials = u.full_name.split.map { |w| w[0] }.first(2).join.upcase
            div(class: "flex items-center gap-[10px]") do
              render UI::Avatar.new(initials, size: :sm)
              div do
                p(class: TYPE_BODY_MD) { plain u.full_name }
                p(class: TYPE_CAPTION) { plain u.email }
              end
            end
          end

          t.column("Role") do |u|
            roles = u.roles
            if roles.empty?
              span(class: TYPE_CAPTION) { plain "No role" }
            else
              div(class: "flex flex-wrap gap-1") do
                roles.first(2).each do |role_obj|
                  bg = role_obj.scope == "internal" ? "#dbeafe" : "#f3f4f6"
                  fg = role_obj.scope == "internal" ? "#1d4ed8" : MUTED_TEXT
                  span(class: "text-[11px] font-semibold px-2 py-[2px] rounded-full",
                       style: "background:#{bg};color:#{fg}") { plain role_obj.name }
                end
                if roles.size > 2
                  span(class: "text-[11px] text-gray-400") { plain "+#{roles.size - 2}" }
                end
              end
            end
          end

          t.column("Type") do |u|
            if u.kind == "internal_staff"
              span(class: "badge-blue text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Staff" }
            else
              span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[2px] rounded-full") { plain "Merchant" }
            end
          end

          t.column("Last active") do |u|
            ts = u.last_sign_in_at
            span(class: TYPE_CAPTION) { plain(ts ? ts.strftime("%d %b %Y") : "Never") }
          end

          t.column("Joined") { |u| plain u.created_at.strftime("%d %b %Y") }

          t.actions do |u|
            a(href: team_user_path(u), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
            if can_invite
              div(class: DROPDOWN_SEP)
              form(action: suspend_team_user_path(u), method: "post",
                   data: { turbo_confirm: "Suspend #{u.full_name}? They will lose portal access immediately." }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: DROPDOWN_ITEM_DANGER) do
                  render UI::Icon.new(:archive, class: ICON_SM)
                  plain "Suspend"
                end
              end
            end
          end
        end
      end

      def invite_dialog
        dialog(id: "invite-member-dialog",
               class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[480px] bg-white") do
          div(class: "px-6 py-[22px] border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Invite team member" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "They'll receive an email to set up their account." }
          end
          form(action: team_invite_user_path, method: "post",
               class: "px-6 py-[22px] flex flex-col gap-[14px]") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            div(class: "grid grid-cols-2 gap-3") do
              render UI::InputField.new(name: "first_name", label: "First name", required: true)
              render UI::InputField.new(name: "last_name",  label: "Last name",  required: true)
            end
            render UI::InputField.new(name: "email", label: "Email address", type: "email", required: true)
            div do
              p(class: "#{TYPE_MICRO} mb-1.5") { plain "Role" }
              select(name: "role_key", required: true, class: "#{SELECT_FIELD} cursor-pointer") do
                option(value: "") { plain "Select a role…" }
                ROLES.first(4).each do |(lbl, val)|
                  option(value: val) { plain lbl }
                end
              end
            end
            div(class: "flex gap-[10px] justify-end mt-1") do
              render UI::Button.new(variant: :secondary,
                     data: { action: "click->dialog#close", dialog_target_param: "invite-member-dialog" }) { plain "Cancel" }
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "Send invitation"
              end
            end
          end
        end
      end
    end
  end
end
