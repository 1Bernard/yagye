# frozen_string_literal: true

module Team
  module Roles
    class IndexView < ApplicationComponent
      include UI::Theme

      ROLE_DESCRIPTIONS = {
        "merchant_owner"      => "Full control over the merchant account. Can manage team, API keys, and all settings.",
        "merchant_finance"    => "Access to financial data, payouts, and settlement reports.",
        "merchant_developer"  => "API key management and webhook configuration.",
        "merchant_support"    => "View transactions and customers. Handle disputes.",
        "ops_analyst"         => "Read-only access to all merchant data and KYB applications.",
        "ops_manager"         => "Full operational access. Can approve KYB and manage merchants.",
        "compliance_analyst"  => "View KYB documents, AML screening, and compliance reports.",
        "compliance_manager"  => "Approve or reject KYB applications and manage compliance rules."
      }.freeze

      def initialize(roles: [])
        @roles = roles
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_roles,
          title:      "Roles & Permissions",
          breadcrumbs: [
            { label: "Team",               url: team_users_path },
            { label: "Roles & Permissions" }
          ]
        ) do
          page_header
          scope_notice
          roles_grid
          permissions_matrix
        end
      end

      private

      def page_header
        div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:20px") do
          div do
            p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Team" }
            h1(style: TYPE_DISPLAY) { "Roles & Permissions" }
          end
        end
      end

      def scope_notice
        div(style: "background:#eff6ff;border:1px solid #bfdbfe;border-radius:12px;padding:14px 18px;" \
                   "display:flex;gap:10px;align-items:flex-start;margin-bottom:24px") do
          span(style: "display:flex;width:16px;height:16px;color:#3b82f6;flex-shrink:0;margin-top:1px") do
            render UI::Icon.new(:info_circle, class: "w-full h-full")
          end
          div do
            p(style: "font-size:13px;font-weight:600;color:#1d4ed8;margin-bottom:2px") { "System-defined roles" }
            p(style: "#{TYPE_CAPTION};color:#3b82f6") do
              "Roles are predefined by Yagye. Assign roles to team members via the Users page. " \
              "Custom roles are planned for a future release."
            end
          end
        end
      end

      def roles_grid
        merchant_roles  = @roles.select { |r| r.scope == "merchant" }
        internal_roles  = @roles.select { |r| r.scope == "internal" }

        div(style: "display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-bottom:32px") do
          role_scope_section("Merchant roles",    merchant_roles, "merchant")
          role_scope_section("Yagye staff roles", internal_roles, "internal")
        end
      end

      def role_scope_section(title, roles, scope)
        badge_bg = scope == "internal" ? "#dbeafe" : "#f3f4f6"
        badge_fg = scope == "internal" ? "#1d4ed8"  : MUTED_TEXT
        label    = scope == "internal" ? "Staff"     : "Merchant"

        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
          div(style: "padding:16px 20px;border-bottom:1px solid #{BORDER};display:flex;" \
                     "align-items:center;gap:8px") do
            span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:16px;" \
                        "background:#{badge_bg};color:#{badge_fg}") { label }
            p(style: TYPE_TITLE) { title }
          end
          div(style: "padding:16px 20px;display:flex;flex-direction:column;gap:12px") do
            if roles.empty?
              p(style: TYPE_CAPTION) { "No roles seeded yet." }
            else
              roles.each { |role| role_card(role, badge_bg, badge_fg) }
            end
          end
        end
      end

      def role_card(role, badge_bg, badge_fg)
        user_count = role.user_roles.size
        perm_count = role.permissions.size
        desc       = ROLE_DESCRIPTIONS.fetch(role.key, role.description.to_s)

        div(style: "padding:14px;background:#{SURFACE};border:1px solid #{BORDER};border-radius:12px") do
          div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:6px") do
            p(style: TYPE_BODY_MD) { role.name }
            div(style: "display:flex;align-items:center;gap:12px;flex-shrink:0") do
              div(style: "text-align:center") do
                p(style: "font-size:16px;font-weight:700;color:#{INK}") { user_count.to_s }
                p(style: "font-size:10px;color:#{MUTED_TEXT}") { "users" }
              end
              div(style: "text-align:center") do
                p(style: "font-size:16px;font-weight:700;color:#{INK}") { perm_count.to_s }
                p(style: "font-size:10px;color:#{MUTED_TEXT}") { "perms" }
              end
            end
          end
          p(style: TYPE_CAPTION) { desc }
        end
      end

      def permissions_matrix
        all_perms = @roles.flat_map(&:permissions).uniq.sort_by(&:key)
        return if all_perms.empty?

        grouped = all_perms.group_by { |p| p.key.split(".").first }

        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
          div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
            p(style: TYPE_TITLE) { "Permission matrix" }
            p(style: "#{TYPE_CAPTION};margin-top:3px") do
              "Which role grants each permission."
            end
          end
          div(style: "overflow-x:auto") do
            table(style: "width:100%;border-collapse:collapse;min-width:600px") do
              matrix_header
              matrix_body(grouped)
            end
          end
        end
      end

      def matrix_header
        thead do
          tr(style: "border-bottom:1px solid #{BORDER}") do
            th(style: "#{TABLE_TH};text-align:left;padding-left:24px") { "Permission" }
            @roles.each do |role|
              th(style: "#{TABLE_TH};text-align:center;white-space:nowrap;min-width:80px") { role.name }
            end
          end
        end
      end

      def matrix_body(grouped)
        tbody do
          grouped.each do |group, perms|
            tr(style: "background:#{SURFACE}") do
              td(colspan: @roles.size + 1,
                 style: "padding:8px 24px;#{TYPE_MICRO};letter-spacing:0.12em") { group.gsub("_", " ").upcase }
            end

            perms.each do |perm|
              tr(style: "border-bottom:1px solid #{BORDER}") do
                td(style: "#{TABLE_CELL};color:#{BODY_TEXT};padding-left:24px") do
                  perm.key.split(".").last.gsub("_", " ").capitalize
                end
                @roles.each do |role|
                  has = role.permissions.include?(perm)
                  td(style: "#{TABLE_CELL};text-align:center") do
                    if has
                      span(style: "display:inline-flex;width:16px;height:16px;color:#16a34a") do
                        render UI::Icon.new(:check, class: "w-full h-full")
                      end
                    else
                      span(style: "display:inline-block;width:12px;height:1px;background:#{BORDER_MED};margin:auto")
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
