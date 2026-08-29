# frozen_string_literal: true

module Team
  module Users
    class ShowPage < ApplicationComponent
      include UI::Theme

      def initialize(user:, roles: [], can_manage: false)
        @user       = user
        @roles      = roles
        @can_manage = can_manage
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_users,
          title:      @user.full_name,
          breadcrumbs: [
            { label: "Team",  url: team_users_path },
            { label: "Users", url: team_users_path },
            { label: @user.full_name }
          ]
        ) do
          div(style: "display:grid;grid-template-columns:320px 1fr;gap:24px;align-items:start") do
            left_panel
            right_panel
          end
        end
      end

      private

      def left_panel
        div(style: "display:flex;flex-direction:column;gap:20px") do
          profile_card
          danger_zone if @can_manage
        end
      end

      def right_panel
        div(style: "display:flex;flex-direction:column;gap:20px") do
          roles_card
          permissions_card
          activity_card
        end
      end

      # ── Profile card ──────────────────────────────────────────────────────────

      def profile_card
        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:24px") do
          div(style: "display:flex;flex-direction:column;align-items:center;gap:12px;margin-bottom:20px;" \
                     "padding-bottom:20px;border-bottom:1px solid #{BORDER}") do
            render UI::Avatar.new(initials, size: :xl)
            div(style: "text-align:center") do
              p(style: TYPE_TITLE) { @user.full_name }
              p(style: TYPE_CAPTION) { @user.email }
            end
            kind_badge
          end
          div(style: "display:flex;flex-direction:column;gap:12px") do
            profile_row("Joined",       @user.created_at.strftime("%d %b %Y"))
            profile_row("Last sign in", @user.last_sign_in_at&.strftime("%d %b %Y, %H:%M") || "Never")
            profile_row("Sign in count", @user.sign_in_count.to_s)
            profile_row("2FA",          @user.otp_required_for_login ? "Enabled" : "Disabled")
          end
        end
      end

      def profile_row(label, value)
        div(style: "display:flex;align-items:center;justify-content:space-between") do
          p(style: TYPE_CAPTION) { label }
          p(style: TYPE_BODY_MD) { value }
        end
      end

      def kind_badge
        if @user.internal_staff?
          span(style: "font-size:11px;font-weight:600;padding:3px 12px;border-radius:16px;background:#dbeafe;color:#1d4ed8") { "Yagye Staff" }
        else
          span(style: "font-size:11px;font-weight:600;padding:3px 12px;border-radius:16px;background:#f3f4f6;color:#{MUTED_TEXT}") { "Merchant user" }
        end
      end

      def danger_zone
        div(style: "background:#fff;border:1px solid #fca5a5;border-radius:16px;padding:20px 24px") do
          p(style: "font-size:13px;font-weight:600;color:#dc2626;margin-bottom:12px") { "Danger zone" }
          div(style: "display:flex;flex-direction:column;gap:8px") do
            button(type: "button", class: BTN_DANGER, style: "width:100%;justify-content:center") do
              render UI::Icon.new(:archive, class: ICON_SM)
              "Suspend user"
            end
            button(type: "button", class: BTN_DANGER, style: "width:100%;justify-content:center") do
              render UI::Icon.new(:x, class: ICON_SM)
              "Remove from team"
            end
          end
        end
      end

      # ── Roles card ────────────────────────────────────────────────────────────

      def roles_card
        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
          div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER};display:flex;" \
                     "align-items:center;justify-content:space-between") do
            p(style: TYPE_TITLE) { "Assigned roles" }
            button(type: "button", class: BTN_SECONDARY, style: @can_manage ? "" : "display:none") do
              render UI::Icon.new(:edit, class: ICON_SM)
              "Edit roles"
            end
          end
          div(style: "padding:20px 24px") do
            if @roles.empty?
              p(style: TYPE_CAPTION) { "No roles assigned. Assign a role to grant access." }
            else
              div(style: "display:flex;flex-direction:column;gap:10px") do
                @roles.each { |role| role_row(role) }
              end
            end
          end
        end
      end

      def role_row(role)
        scope_color = role.scope == "internal" ? "#1d4ed8" : MUTED_TEXT
        scope_bg    = role.scope == "internal" ? "#dbeafe" : "#f3f4f6"

        div(style: "display:flex;align-items:center;justify-content:space-between;padding:12px 14px;" \
                   "background:#{SURFACE};border-radius:12px;border:1px solid #{BORDER}") do
          div(style: "display:flex;align-items:center;gap:10px") do
            span(style: "font-size:11px;font-weight:600;padding:2px 9px;border-radius:16px;" \
                        "background:#{scope_bg};color:#{scope_color}") { role.scope.capitalize }
            p(style: TYPE_BODY_MD) { role.name }
          end
          p(style: TYPE_CAPTION) { "#{role.permissions.size} permissions" }
        end
      end

      # ── Permissions card ──────────────────────────────────────────────────────

      def permissions_card
        all_perms = @roles.flat_map(&:permissions).uniq

        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
          div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
            div(style: "display:flex;align-items:center;justify-content:space-between") do
              p(style: TYPE_TITLE) { "Effective permissions" }
              p(style: TYPE_CAPTION) { "#{all_perms.size} permissions from #{@roles.size} #{@roles.size == 1 ? 'role' : 'roles'}" }
            end
          end
          div(style: "padding:16px 24px") do
            if all_perms.empty?
              p(style: TYPE_CAPTION) { "No permissions. Assign a role to grant access." }
            else
              grouped = all_perms.group_by { |p| p.key.split(".").first }
              div(style: "display:grid;grid-template-columns:1fr 1fr;gap:12px") do
                grouped.each do |group, perms|
                  perm_group(group, perms)
                end
              end
            end
          end
        end
      end

      def perm_group(group, perms)
        div(style: "background:#{SURFACE};border-radius:12px;padding:12px 14px;border:1px solid #{BORDER}") do
          p(style: "#{TYPE_MICRO};margin-bottom:8px") { group.gsub("_", " ") }
          div(style: "display:flex;flex-direction:column;gap:5px") do
            perms.each do |perm|
              div(style: "display:flex;align-items:center;gap:6px") do
                span(style: "display:flex;width:12px;height:12px;color:#16a34a;flex-shrink:0") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
                p(style: "font-size:11.5px;color:#{BODY_TEXT}") { perm.key.split(".").last.gsub("_", " ").capitalize }
              end
            end
          end
        end
      end

      # ── Activity card ─────────────────────────────────────────────────────────

      def activity_card
        div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
          div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
            p(style: TYPE_TITLE) { "Recent activity" }
          end
          div(style: "padding:40px 24px;text-align:center") do
            span(style: "display:flex;width:32px;height:32px;color:#{SUBTLE_TEXT};margin:0 auto 10px") do
              render UI::Icon.new(:clock, class: "w-full h-full")
            end
            p(style: TYPE_CAPTION) { "Activity log will be available in a future release." }
          end
        end
      end

      def initials
        @user.full_name.split.map { |w| w[0] }.first(2).join.upcase
      end
    end
  end
end
