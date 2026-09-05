# frozen_string_literal: true

module Team
  module Users
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(users: [], can_invite: false, query: nil, role: nil, status: nil, view: "list")
        @users      = users
        @can_invite = can_invite
        @query      = query
        @role       = role
        @status     = status
        @view       = view
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
          div(data: { controller: "dialog" }) do
            render UI::PageHeader.new(title: "Team members", subtitle: "Manage who has access to your account.") do
              if @can_invite
                render UI::Button.new(variant: :primary,
                       data: { action: "click->dialog#open", dialog_target_param: "invite-member-dialog" }) do
                  render UI::Icon.new(:plus, class: ICON_SM)
                  plain "Invite member"
                end
              end
            end
            @view == "grid" ? users_grid_section : users_list_section
            filter_dialog
            invite_dialog if @can_invite
          end
        end
      end

      private

      # ── Toolbar (shared between list + grid) ──────────────────────────────────

      def toolbar_content
        filter_count = [ @role.present?, @status.present? ].count(true)

        form(action: team_users_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search by name or email…",
                  class: FILTER_SEARCH_INPUT)
          end
        end

        div(class: "flex items-center gap-2") do
          export_dropdown
          filter_btn(filter_count)
          view_toggle
        end
      end

      def export_dropdown
        export_base = { q: @query, role: @role, status: @status }.reject { |_, v| v.blank? }

        div(class: "relative", data: { controller: "dropdown" }) do
          button(type: "button",
                 class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 rounded-[9px] " \
                        "text-[12.5px] font-medium text-gray-600 bg-white cursor-pointer transition-colors " \
                        "hover:border-gray-400 hover:text-gray-800",
                 data: { action: "click->dropdown#toggle" }) do
            render UI::Icon.new(:download, class: "w-3 h-3")
            plain "Export"
            render UI::Icon.new(:chev, class: "w-3 h-3 ml-px text-gray-400")
          end
          div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[170px]",
              data: { dropdown_target: "menu" }) do
            p(class: DROPDOWN_TITLE) { plain "Export as" }
            a(href: team_users_path(export_base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "CSV"
            end
            a(href: team_users_path(export_base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "Excel (.xlsx)"
            end
            a(href: team_users_path(export_base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "PDF"
            end
          end
        end
      end

      def filter_btn(filter_count)
        button(type: "button",
               class: "inline-flex items-center gap-[5px] px-3 h-8 border rounded-[9px] " \
                      "text-[12.5px] font-medium bg-white cursor-pointer transition-colors " \
                      "#{filter_count > 0 ? 'border-gray-400 text-gray-900' : 'border-gray-200 text-gray-600'} " \
                      "hover:border-gray-400",
               data: { action: "click->dialog#open", dialog_target_param: "filter-dialog" }) do
          render UI::Icon.new(:filter, class: "w-3 h-3")
          plain "Filters"
          if filter_count > 0
            span(class: "ml-[2px] inline-flex items-center justify-center w-4 h-4 rounded-full " \
                        "bg-[#3D47F5] text-white text-[9px] font-bold leading-none") do
              plain filter_count.to_s
            end
          end
        end
      end

      def view_toggle
        base = { q: @query, role: @role, status: @status }.reject { |_, v| v.blank? }

        div(class: "flex items-center bg-gray-100 p-[3px] rounded-[10px] gap-[2px]") do
          [ [ :list, "list" ], [ :grid, "grid" ] ].each do |(icon_name, view_val)|
            active = @view == view_val
            attrs  = { href: team_users_path(base.merge(view: view_val)),
                       class: "flex items-center justify-center w-[30px] h-[30px] rounded-[8px] transition-all" }
            if active
              attrs[:class] += " bg-white text-gray-800"
              attrs[:style] = "box-shadow:0 1px 3px rgba(0,0,0,0.10),0 1px 2px rgba(0,0,0,0.06)"
            else
              attrs[:class] += " text-gray-400 hover:text-gray-600"
            end
            a(**attrs) { render UI::Icon.new(icon_name, class: "w-[13px] h-[13px]") }
          end
        end
      end

      # ── Grid view ─────────────────────────────────────────────────────────────

      def users_grid_section
        div(class: "bg-white border border-gray-100 rounded-2xl mb-4") do
          div(class: "flex items-center justify-between px-5 py-3.5") do
            toolbar_content
          end
        end

        if @users.empty?
          div(class: "flex flex-col items-center justify-center text-center py-16") do
            div(class: "w-12 h-12 rounded-2xl icon-brand flex items-center justify-center mb-3") do
              span(class: "flex w-6 h-6") { render UI::Icon.new(:users, class: "w-full h-full") }
            end
            p(class: "#{TYPE_BODY_MD} mb-1") { plain "No team members found" }
            p(class: TYPE_CAPTION) { plain "Invite someone to get started." }
          end
        else
          div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3") do
            @users.each { |u| user_grid_card(u) }
          end
        end
      end

      def user_grid_card(u)
        initials_str = u.full_name.split.map { |w| w[0] }.first(2).join.upcase
        roles        = u.roles

        a(href: team_user_path(u),
          class: "group block bg-white border border-gray-100 rounded-2xl p-5 no-underline #{CARD_HOVER}") do
          div(class: "mb-4") { render UI::Avatar.new(initials_str, size: :lg) }

          div(class: "mb-3") do
            p(class: "text-[13.5px] font-semibold text-gray-900 leading-tight tracking-[-0.01em]") do
              plain u.full_name
            end
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain u.email }
          end

          div(class: "flex flex-wrap gap-1.5 min-h-[22px]") do
            if roles.empty?
              span(class: TYPE_CAPTION) { plain "No role" }
            else
              roles.first(2).each do |r|
                badge = r.scope == "internal" ? "badge-blue" : "badge-gray"
                span(class: "#{badge} text-[10.5px] font-semibold px-2 py-[2px] rounded-full") { plain r.name }
              end
              if roles.size > 2
                span(class: "text-[10.5px] text-gray-400 font-medium") { plain "+#{roles.size - 2}" }
              end
            end
          end

          div(class: "flex items-center justify-between mt-4 pt-3 border-t border-gray-50") do
            p(class: TYPE_CAPTION) { plain "Joined #{u.created_at.strftime('%d %b %Y')}" }
            span(class: "flex w-[13px] h-[13px] text-gray-300 flex-shrink-0 " \
                        "group-hover:text-gray-500 group-hover:translate-x-[2px] transition-all") do
              render UI::Icon.new(:chev_right, class: "w-full h-full")
            end
          end
        end
      end

      # ── List view ─────────────────────────────────────────────────────────────

      def users_list_section
        can_invite = @can_invite

        render UI::Datatable.new(records: @users,
                                 empty_message: "No team members found. Invite someone to get started.") do |t|
          t.header { toolbar_content }

          t.column("Member") do |u|
            is = u.full_name.split.map { |w| w[0] }.first(2).join.upcase
            div(class: "flex items-center gap-[10px]") do
              render UI::Avatar.new(is, size: :sm)
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
                roles.first(2).each do |r|
                  badge = r.scope == "internal" ? "badge-blue" : "badge-gray"
                  span(class: "#{badge} text-[11px] font-semibold px-2 py-[2px] rounded-full") { plain r.name }
                end
                span(class: "text-[11px] text-gray-400") { plain "+#{roles.size - 2}" } if roles.size > 2
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

          t.column("Joined") do |u|
            span(class: TYPE_CAPTION) { plain u.created_at.strftime("%d %b %Y") }
          end

          t.actions do |u|
            a(href: team_user_path(u), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View profile"
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

      # ── Filter drawer ─────────────────────────────────────────────────────────

      def filter_dialog
        dialog(id: "filter-dialog", class: "side-panel bg-white w-[400px] max-w-[95vw]") do
          div(class: "flex flex-col h-full") do
            div(class: "flex-shrink-0 flex items-start justify-between px-6 py-5 border-b border-gray-100") do
              div do
                p(class: TYPE_TITLE) { plain "Filter members" }
                p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by status or role." }
              end
              button(type: "button", class: XBTN,
                     data: { action: "click->dialog#close", dialog_target_param: "filter-dialog" }) do
                plain "✕"
              end
            end

            form(action: team_users_path, method: "get",
                 class: "flex flex-col flex-1 overflow-hidden") do
              input(type: "hidden", name: "q", value: @query) if @query.present?

              div(class: "flex-1 overflow-y-auto") do
                div(class: "px-6 py-5 border-b border-gray-100") do
                  filter_section_label("Status", :check_circle, "brand")
                  div(class: "flex flex-wrap gap-2 mt-3") do
                    [ [ "All", "" ], [ "Active", "active" ], [ "Suspended", "suspended" ] ].each do |(lbl, val)|
                      label(class: "cursor-pointer") do
                        input(type: "radio", name: "status", value: val,
                              checked: (val == @status.to_s || (val == "" && @status.blank?)),
                              class: "sr-only peer")
                        span(class: CHIP) { plain lbl }
                      end
                    end
                  end
                end

                div(class: "px-6 py-5") do
                  filter_section_label("Role", :users, "purple")
                  p(class: "text-[10px] font-bold text-gray-400 uppercase tracking-[0.12em] mt-5 mb-2") { plain "Merchant" }
                  Portal::RoleMetadata::MERCHANT.each do |r|
                    filter_role_row(r[:label], r[:key], r[:icon], r[:palette], hint: r[:hint])
                  end
                  p(class: "text-[10px] font-bold text-gray-400 uppercase tracking-[0.12em] mt-5 mb-2") { plain "Internal" }
                  Portal::RoleMetadata::INTERNAL.each do |r|
                    filter_role_row(r[:label], r[:key], r[:icon], r[:palette], hint: r[:hint])
                  end
                end
              end

              div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
                a(href: team_users_path(@query.present? ? { q: @query } : {}),
                  class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors no-underline") do
                  plain "Clear all"
                end
                button(type: "submit", class: BTN_PRIMARY) { plain "Apply filters" }
              end
            end
          end
        end
      end

      def filter_section_label(label_text, icon, palette)
        div(class: "flex items-center gap-2") do
          div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
            span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
          end
          p(class: "text-[12px] font-semibold text-gray-700") { plain label_text }
        end
      end

      def filter_role_row(label_text, value, icon, palette, hint: nil)
        label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
          input(type: "radio", name: "role", value: value,
                checked: (value == @role.to_s || (value == "" && @role.blank?)),
                class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer")
          div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
            span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
          end
          div do
            span(class: TYPE_BODY_MD) { plain label_text }
            p(class: TYPE_CAPTION) { plain hint } if hint
          end
        end
      end

      # ── Invite drawer ─────────────────────────────────────────────────────────

      def invite_dialog
        dialog(id: "invite-member-dialog", class: "side-panel bg-white w-[520px] max-w-[95vw]") do
          div(class: "flex flex-col h-full") do
            div(class: "flex-shrink-0 flex items-start justify-between px-6 py-5 border-b border-gray-100") do
              div do
                p(class: TYPE_TITLE) { plain "Invite team member" }
                p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "They'll receive an email to set up their account." }
              end
              button(type: "button", class: XBTN,
                     data: { action: "click->dialog#close", dialog_target_param: "invite-member-dialog" }) do
                plain "✕"
              end
            end

            form(action: team_invite_user_path, method: "post",
                 class: "flex flex-col flex-1 overflow-hidden") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div(class: "flex-1 overflow-y-auto px-6 py-5 flex flex-col gap-6") do
                div(class: "flex flex-col gap-4") do
                  div do
                    p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") { plain "Contact details" }
                    div(class: "flex flex-col gap-3") do
                      div(class: "grid grid-cols-2 gap-3") do
                        render UI::InputField.new(name: "first_name", label: "First name", required: true)
                        render UI::InputField.new(name: "last_name",  label: "Last name",  required: true)
                      end
                      render UI::InputField.new(name: "email", label: "Email address", type: "email", required: true)
                    end
                  end
                end

                div do
                  p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") { plain "Assign a role" }
                  p(class: "#{TYPE_CAPTION} mb-4") { plain "Choose the role that best matches this person's responsibilities." }

                  div(class: "flex flex-col gap-2") do
                    p(class: "#{TYPE_MICRO} text-gray-400 mb-1") { plain "Merchant" }
                    Portal::RoleMetadata::MERCHANT.each do |r|
                      invite_role_card(r[:label], r[:key], r[:hint], icon: r[:icon], palette: r[:palette])
                    end
                  end

                  div(class: "flex flex-col gap-2 mt-5") do
                    p(class: "#{TYPE_MICRO} text-gray-400 mb-1") { plain "Internal" }
                    Portal::RoleMetadata::INTERNAL.each do |r|
                      invite_role_card(r[:label], r[:key], r[:hint], icon: r[:icon], palette: r[:palette])
                    end
                  end
                end
              end

              div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
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

      def invite_role_card(lbl, val, hint, icon:, palette:)
        card_id = "role-#{val}"
        label(for: card_id,
              class: "flex items-center gap-3 px-4 py-3 rounded-xl border border-gray-200 " \
                     "cursor-pointer transition-all hover:border-gray-300 " \
                     "has-[:checked]:border-[#3D47F5] has-[:checked]:bg-[rgba(61,71,245,0.04)]") do
          input(type: "radio", name: "role_key", value: val, id: card_id, required: true, class: "sr-only")
          div(class: "w-8 h-8 rounded-[10px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(icon, class: "w-full h-full") }
          end
          div(class: "flex-1 min-w-0") do
            p(class: "text-[13px] font-semibold text-gray-800 leading-tight") { plain lbl }
            p(class: "text-[11px] text-gray-400 leading-tight mt-px") { plain hint }
          end
          span(class: "role-card-check flex w-[15px] h-[15px] flex-shrink-0 text-[#3D47F5]") do
            render UI::Icon.new(:check, class: "w-full h-full")
          end
        end
      end
    end
  end
end
