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
            { label: "Team",  url: team_users_path },
            { label: "Users", url: team_users_path },
            { label: @user.full_name }
          ]
        ) do
          render UI::Grid.new(columns: :profile) do
            left_panel
            right_panel
          end
        end
      end

      private

      def left_panel
        div(class: "flex flex-col gap-5") do
          profile_card
          danger_zone if @can_manage
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
        div(class: "bg-white border border-gray-100 rounded-2xl p-6") do
          div(class: "flex flex-col items-center gap-3 mb-5 pb-5 border-b border-gray-100") do
            render UI::Avatar.new(initials, size: :xl)
            div(class: "text-center") do
              p(class: TYPE_TITLE) { plain @user.full_name }
              p(class: TYPE_CAPTION) { plain @user.email }
            end
            kind_badge
          end
          div(class: "flex flex-col gap-3") do
            profile_row("Joined",        @user.created_at.strftime("%d %b %Y"))
            profile_row("Last sign in",  @user.last_sign_in_at&.strftime("%d %b %Y, %H:%M") || "Never")
            profile_row("Sign in count", @user.sign_in_count.to_s)
            profile_row("2FA",           @user.otp_required_for_login ? "Enabled" : "Disabled")
          end
        end
      end

      def profile_row(label, value)
        div(class: "flex items-center justify-between") do
          p(class: TYPE_CAPTION) { plain label }
          p(class: TYPE_BODY_MD) { plain value }
        end
      end

      def kind_badge
        if @user.internal_staff?
          span(class: "badge-blue text-[11px] font-semibold px-3 py-[3px] rounded-2xl") do
            plain "Yagye Staff"
          end
        else
          span(class: "text-[11px] font-semibold px-3 py-[3px] rounded-2xl bg-gray-100 text-gray-500") do
            plain "Merchant user"
          end
        end
      end

      def danger_zone
        div(class: "bg-white border border-red-300 rounded-2xl px-6 py-5") do
          p(class: "text-[13px] font-semibold text-red-600 mb-3") { plain "Danger zone" }
          div(class: "flex flex-col gap-2") do
            form(action: suspend_team_user_path(@user), method: "post",
                 data: { turbo_confirm: "Suspend #{@user.full_name}? They will lose access immediately." }) do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render UI::Button.new(variant: :danger, type: "submit", class: "w-full justify-center") do
                render UI::Icon.new(:archive, class: ICON_SM)
                plain "Suspend user"
              end
            end
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

      def role_row(role)
        badge = role.scope == "internal" ? "badge-blue" : "badge-gray"

        div(class: "flex items-center justify-between px-[14px] py-3 bg-gray-100 rounded-xl border border-gray-100") do
          div(class: "flex items-center gap-[10px]") do
            span(class: "#{badge} text-[11px] font-semibold px-[9px] py-[2px] rounded-2xl") do
              plain role.scope.capitalize
            end
            p(class: TYPE_BODY_MD) { plain role.name }
          end
          p(class: TYPE_CAPTION) { plain "#{role.permissions.size} permissions" }
        end
      end

      # ── Permissions card ──────────────────────────────────────────────────────

      def permissions_card
        all_perms = @roles.flat_map(&:permissions).uniq

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
              div(class: "grid grid-cols-2 gap-3") do
                grouped.each { |group, perms| perm_group(group, perms) }
              end
            end
          end
        end
      end

      def perm_group(group, perms)
        div(class: "bg-gray-50 rounded-xl px-[14px] py-3 border border-gray-100") do
          p(class: "#{TYPE_MICRO} mb-2") { plain group.gsub("_", " ") }
          div(class: "flex flex-col gap-[5px]") do
            perms.each do |perm|
              div(class: "flex items-center gap-1.5") do
                span(class: "flex w-3 h-3 text-green-600 flex-shrink-0") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
                p(class: "text-[11.5px] text-gray-700") do
                  plain perm.key.split(".").last.gsub("_", " ").capitalize
                end
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
            div(class: "py-5 text-center") do
              span(class: "flex w-8 h-8 text-gray-300 mx-auto mb-[10px]") do
                render UI::Icon.new(:clock, class: "w-full h-full")
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
