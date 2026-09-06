# frozen_string_literal: true

module Team
  module Roles
    class IndexView < ApplicationComponent
      include UI::Theme

      SCOPE_ICON  = { "merchant" => :building, "internal" => :users }.freeze
      SCOPE_COLOR = { "merchant" => "icon-green", "internal" => "icon-purple" }.freeze
      SCOPE_BADGE = { "merchant" => "badge-green", "internal" => "badge-purple" }.freeze

      def initialize(roles: [], can_manage: false)
        @roles      = roles
        @can_manage = can_manage
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_roles,
          title:      "Roles & Permissions",
          breadcrumbs: [
            { label: "Team",                href: team_users_path },
            { label: "Roles & Permissions" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Roles & permissions",
            subtitle: "Define what each team member can see and do across Yagye."
          ) do
            if @can_manage
              render UI::Button.new(variant: :primary, href: new_team_role_path,
                                   data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "New role"
              end
            end
          end

          div(class: "flex flex-col gap-5") do
            stats_bar
            roles_section
            matrix_card
          end
        end
      end

      private

      # ── Stats ──────────────────────────────────────────────────────────────────

      def stats_bar
        merchant_count = @roles.count { |r| r.scope == "merchant" }
        internal_count = @roles.count { |r| r.scope == "internal" }
        total_perms    = @roles.sum { |r| r.permissions.size }

        div(class: "grid grid-cols-4 gap-3") do
          stat_tile("Total roles",       @roles.size,    :key,       "icon-brand")
          stat_tile("Merchant roles",    merchant_count, :building,  "icon-green")
          stat_tile("Internal roles",    internal_count, :users,     "icon-purple")
          stat_tile("Permission grants", total_perms,    :shield,    "icon-teal")
        end
      end

      def stat_tile(label, value, icon_name, color_cls)
        div(class: "bg-white border border-gray-100 rounded-2xl px-5 py-[18px] flex items-center gap-4") do
          div(class: "w-10 h-10 rounded-xl #{color_cls} flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[18px] h-[18px]") { render UI::Icon.new(icon_name, class: "w-full h-full") }
          end
          div do
            p(class: "text-[22px] font-bold text-gray-900 leading-none tabular-nums") { plain value.to_s }
            p(class: "text-[11px] text-gray-400 mt-[4px] leading-none") { plain label }
          end
        end
      end

      # ── Role sections ──────────────────────────────────────────────────────────

      def roles_section
        merchant_roles = @roles.select { |r| r.scope == "merchant" }
        internal_roles = @roles.select { |r| r.scope == "internal" }

        div(class: "flex flex-col gap-4") do
          scope_section("Merchant roles",    merchant_roles, "merchant")
          scope_section("Yagye staff roles", internal_roles, "internal")
        end
      end

      def scope_section(title, roles, scope)
        icon_name  = SCOPE_ICON.fetch(scope, :key)
        color_cls  = SCOPE_COLOR.fetch(scope, "icon-brand")
        badge_cls  = SCOPE_BADGE.fetch(scope, "badge-gray")

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "flex items-center justify-between px-6 py-4 border-b border-gray-100") do
            div(class: "flex items-center gap-3") do
              div(class: "w-8 h-8 rounded-lg #{color_cls} flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(icon_name, class: "w-full h-full") }
              end
              p(class: "text-[14px] font-semibold text-gray-900") { plain title }
            end
            span(class: "#{badge_cls} text-[10.5px] font-semibold px-[10px] py-[3px] rounded-full") do
              plain "#{roles.size} role#{roles.size == 1 ? '' : 's'}"
            end
          end

          if roles.empty?
            div(class: "px-6 py-10 text-center") do
              p(class: TYPE_CAPTION) { plain "No roles defined yet." }
            end
          else
            div(class: "divide-rows") do
              roles.each { |r| role_row(r, color_cls) }
            end
          end
        end
      end

      def role_row(role, color_cls)
        user_count = role.user_roles.size
        perm_count = role.permissions.size
        deletable  = @can_manage && !role.system_role? && user_count.zero?

        div(class: "flex items-center gap-4 px-6 py-[14px] hover:bg-gray-50/50 transition-colors") do
          div(class: "w-9 h-9 rounded-xl #{color_cls} flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:key, class: "w-full h-full") }
          end

          div(class: "flex-1 min-w-0") do
            div(class: "flex items-center gap-[7px] mb-[3px]") do
              p(class: "text-[13px] font-semibold text-gray-900") { plain role.name }
              if role.system_role?
                span(class: "badge-blue text-[9.5px] font-bold px-[7px] py-[2px] rounded-full leading-tight") do
                  plain "System"
                end
              end
            end
            p(class: "text-[12px] text-gray-400 truncate leading-snug") do
              plain role.description.to_s
            end
          end

          div(class: "flex items-center gap-3 flex-shrink-0") do
            stat_chip(user_count, "users", :users)
            stat_chip(perm_count, "perms", :shield)
          end

          if @can_manage
            div(class: "flex items-center gap-2 flex-shrink-0 ml-2") do
              render UI::Button.new(variant: :secondary, href: edit_team_role_path(role.key),
                                   data: { turbo_frame: "drawer-frame" }) do
                render UI::Icon.new(:edit, class: ICON_SM)
                plain "Edit"
              end
              if deletable
                form(action: team_role_path(role.key), method: "post",
                     data: { turbo_confirm: "Delete \"#{role.name}\"? This cannot be undone." }) do
                  input(type: "hidden", name: "_method",            value: "delete")
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  render UI::Button.new(variant: :danger, type: "submit") do
                    render UI::Icon.new(:x, class: ICON_SM)
                    plain "Delete"
                  end
                end
              end
            end
          end
        end
      end

      def stat_chip(count, label, icon_name)
        div(class: "inline-flex items-center gap-[5px] bg-gray-50 border border-gray-100 " \
                   "rounded-full px-[10px] py-[4px]") do
          span(class: "flex w-[10px] h-[10px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(icon_name, class: "w-full h-full")
          end
          span(class: "text-[11.5px] font-semibold text-gray-700 tabular-nums") { plain count.to_s }
          span(class: "text-[10.5px] text-gray-400") { plain label }
        end
      end

      # ── Permission matrix ──────────────────────────────────────────────────────

      def matrix_card
        all_perms = @roles.flat_map(&:permissions).uniq.sort_by(&:key)
        return if all_perms.empty?

        grouped = all_perms.group_by { |p| p.key.split(".").first }

        render UI::Card.new do |c|
          c.header("Permission matrix") do
            p(class: TYPE_CAPTION) { plain "Which roles include each permission." }
          end
          c.body(padding: false) do
            div(class: "overflow-x-auto") do
              table(class: "w-full border-collapse") do
                matrix_header
                matrix_body(grouped)
              end
            end
          end
        end
      end

      def matrix_header
        thead do
          tr(class: "border-b border-gray-100 bg-gray-50/80") do
            th(class: "#{TABLE_TH} pl-6 py-3 text-left w-[220px]") { plain "Permission" }
            @roles.each do |role|
              th(class: "#{TABLE_TH} py-3 text-center whitespace-nowrap px-3 min-w-[90px]") do
                plain role.name
              end
            end
          end
        end
      end

      def matrix_body(grouped)
        tbody do
          grouped.each do |group, perms|
            tr(class: "bg-gray-50/60") do
              td(colspan: @roles.size + 1,
                 class: "#{TEXT_LABEL} px-6 py-[7px]") do
                plain group.gsub("_", " ")
              end
            end
            perms.each do |perm|
              tr(class: "border-b border-gray-100 hover:bg-gray-50/40 transition-colors") do
                td(class: "#{TABLE_CELL} pl-6 py-[10px]") do
                  plain perm.action.gsub("_", " ").capitalize
                end
                @roles.each do |role|
                  td(class: "py-[10px] text-center px-3") do
                    if role.permissions.include?(perm)
                      span(class: "inline-flex w-[20px] h-[20px] rounded-full items-center " \
                                  "justify-center mx-auto icon-green") do
                        span(class: "flex w-[10px] h-[10px]") do
                          render UI::Icon.new(:check, class: "w-full h-full")
                        end
                      end
                    else
                      span(class: "block w-[10px] h-px bg-gray-200 mx-auto")
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
