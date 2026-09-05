# frozen_string_literal: true

module Team
  module Users
    class ShowView < ApplicationComponent
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
            { label: "Team members", url: team_users_path },
            { label: @user.full_name }
          ]
        ) do
          back_link
          render UI::Grid.new(columns: :profile) do
            left_panel
            right_panel
          end
        end
      end

      private

      def back_link
        a(href: team_users_path,
          class: "group inline-flex items-center gap-[6px] text-[12.5px] font-medium " \
                 "text-gray-400 hover:text-gray-700 no-underline mb-5 transition-colors") do
          span(class: "flex w-[13px] h-[13px] group-hover:-translate-x-[2px] transition-transform") do
            render UI::Icon.new(:chev_left, class: "w-full h-full")
          end
          plain "Team members"
        end
      end

      def left_panel
        div(class: "flex flex-col gap-5") do
          profile_card
          if @can_manage
            render UI::DangerZone.new(
              title:       "Suspend user",
              description: "Immediately revokes access. The user cannot sign in until reinstated.",
              icon:        :archive
            ) do
              form(action: suspend_team_user_path(@user), method: "post",
                   data: { turbo_confirm: "Suspend #{@user.full_name}? They will lose access immediately." }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                render UI::Button.new(variant: :danger, type: "submit") do
                  render UI::Icon.new(:archive, class: ICON_SM)
                  plain "Suspend user"
                end
              end
            end
          end
        end
      end

      def right_panel
        div(class: "flex flex-col gap-5") do
          roles_card
          permissions_card
          activity_card
        end
      end

      # ── Profile card ──────────────────────────────────────────────────────────

      def profile_card
        u         = @user
        suspended = u.respond_to?(:suspended_at) && u.suspended_at.present?
        totp_on   = u.otp_required_for_login

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-6") do
            div(class: "relative inline-block mb-4") do
              render UI::Avatar.new(initials, size: :xl)
              div(class: "absolute -bottom-[3px] -right-[3px] w-4 h-4 rounded-full border-2 border-white",
                  style: "background:#{suspended ? '#9CA3AF' : '#22c55e'}")
            end
            p(class: "text-[16px] font-bold text-gray-900 tracking-[-0.02em] leading-tight mb-[3px]") do
              plain u.full_name
            end
            p(class: "#{TYPE_CAPTION} mb-3") { plain u.email }
            div(class: "flex items-center gap-[6px] flex-wrap") do
              if u.internal_staff?
                span(class: "badge-blue text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Yagye Staff" }
              else
                span(class: "badge-gray text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Merchant" }
              end
              if suspended
                span(class: "badge-amber text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Suspended" }
              else
                span(class: "badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "Active" }
              end
              if totp_on
                span(class: "badge-green text-[11px] font-semibold px-[9px] py-[3px] rounded-full") { plain "2FA on" }
              end
            end
          end

          div(class: "border-t border-gray-100") do
            render UI::DetailRow.new(icon: :calendar,     label: "Joined",       value: u.created_at.strftime("%d %b %Y"))
            render UI::DetailRow.new(icon: :clock,        label: "Last sign-in", value: u.last_sign_in_at&.strftime("%d %b %Y") || "Never")
            render UI::DetailRow.new(icon: :check_circle, label: "Sign-ins",     value: u.sign_in_count.to_s)
            render UI::DetailRow.new(icon: :shield,       label: "Two-factor",   value: totp_on ? "Enabled" : "Not set")
          end
        end
      end

      # ── Roles card ────────────────────────────────────────────────────────────

      def roles_card
        render UI::Card.new do |c|
          c.header("Assigned roles") do
            render UI::Button.new(variant: :secondary, hidden: !@can_manage) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Edit roles"
            end
          end
          c.body do
            if @roles.empty?
              p(class: TYPE_CAPTION) { plain "No roles assigned. Assign a role to grant access." }
            else
              div(class: "flex flex-col gap-[10px]") do
                @roles.each { |role| role_row(role) }
              end
            end
          end
        end
      end

      def role_row(user_role)
        r     = user_role.role
        badge = r.scope == "internal" ? "badge-blue" : "badge-gray"

        div(class: "flex items-center justify-between px-[14px] py-3 bg-gray-100 rounded-xl border border-gray-100") do
          div(class: "flex items-center gap-[10px]") do
            span(class: "#{badge} text-[11px] font-semibold px-[9px] py-[2px] rounded-2xl") { plain r.scope.capitalize }
            p(class: TYPE_BODY_MD) { plain r.name }
          end
          p(class: TYPE_CAPTION) { plain "#{r.permissions.size} permissions" }
        end
      end

      # ── Permissions card ──────────────────────────────────────────────────────

      def permissions_card
        all_perms = @roles.flat_map { |ur| ur.role.permissions }.uniq

        render UI::Card.new do |c|
          c.header("Effective permissions") do
            p(class: TYPE_CAPTION) do
              plain "#{all_perms.size} permissions from #{@roles.size} #{@roles.size == 1 ? 'role' : 'roles'}"
            end
          end
          c.body do
            if all_perms.empty?
              p(class: TYPE_CAPTION) { plain "No permissions. Assign a role to grant access." }
            else
              grouped = all_perms.group_by { |p| p.key.split(".").first }
              div(class: "grid grid-cols-2 gap-x-8 gap-y-5") do
                grouped.each { |group, perms| perm_group(group, perms) }
              end
            end
          end
        end
      end

      def perm_group(group, perms)
        div do
          p(class: "#{TYPE_MICRO} mb-2") { plain group.gsub("_", " ") }
          div(class: "flex flex-col gap-[7px]") do
            perms.each do |perm|
              div(class: "flex items-center gap-[7px]") do
                span(class: "flex w-[12px] h-[12px] text-green-500 flex-shrink-0") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
                p(class: TYPE_BODY) { plain perm.key.split(".").last.gsub("_", " ").capitalize }
              end
            end
          end
        end
      end

      # ── Activity card ─────────────────────────────────────────────────────────

      def activity_card
        render UI::Card.new do |c|
          c.header("Recent activity")
          c.body do
            div(class: "py-5 flex flex-col items-center text-center gap-2") do
              div(class: "w-10 h-10 rounded-xl icon-brand flex items-center justify-center mb-1") do
                span(class: "flex w-5 h-5") { render UI::Icon.new(:clock, class: "w-full h-full") }
              end
              p(class: TYPE_CAPTION) { plain "Activity log will be available in a future release." }
            end
          end
        end
      end

      def initials
        @user.full_name.split.map { |w| w[0] }.first(2).join.upcase
      end
    end
  end
end
