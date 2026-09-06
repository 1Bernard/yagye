# frozen_string_literal: true

module Team
  module Users
    class EditRolesView < ApplicationComponent
      include UI::Theme

      ROLE_META = (Portal::RoleMetadata::MERCHANT + Portal::RoleMetadata::INTERNAL)
                    .index_by { |r| r[:key] }.freeze

      def initialize(user:, available_roles:, current_keys:)
        @user            = user
        @available_roles = available_roles
        @current_keys    = current_keys
      end

      def view_template
        turbo_frame_tag "drawer-frame" do
          role_style
          drawer_header
          div(class: "flex-1 min-h-0 overflow-y-auto") do
            form(action: set_team_user_roles_path(@user), method: "post", id: "edit-roles-form",
                 class: "px-6 pt-5 pb-6 flex flex-col gap-4",
                 data: { turbo_frame: "_top" }) do
              input(type: "hidden", name: "_method",            value: "put")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              effect_notice
              if @available_roles.empty?
                p(class: TYPE_CAPTION) { plain "No roles available for this user type." }
              else
                div(class: "flex flex-col gap-[10px]") do
                  @available_roles.each { |role| role_card(role) }
                end
                no_role_warning
              end
            end
          end
          drawer_footer
        end
      end

      private

      def role_style
        style do
          plain <<~CSS
            .role-opt { transition: border-color 0.12s, background 0.12s; }
            .role-opt:has(input:checked) { border-color: rgba(61,71,245,0.5); background: rgba(61,71,245,0.04); }
            .role-opt:has(input:checked) .role-chk-box { background: #3D47F5; border-color: #3D47F5; }
            .role-opt:has(input:checked) .role-chk-icon { display: flex; }
            .role-chk-icon { display: none; }
            .no-role-warn { display: none; }
            #edit-roles-form:not(:has(input[type=checkbox]:checked)) .no-role-warn { display: flex; }
          CSS
        end
      end

      # ── Header ────────────────────────────────────────────────────────────────

      def drawer_header
        div(class: DRAWER_HEAD) do
          div(class: "flex items-center gap-3 min-w-0") do
            div(class: "w-8 h-8 rounded-lg icon-brand flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:key, class: "w-full h-full") }
            end
            div(class: "min-w-0") do
              p(class: TYPE_MICRO) { plain @user.full_name }
              p(class: "text-[14px] font-semibold truncate", style: "color:var(--ink)") do
                plain "Edit roles"
              end
            end
          end
          button(type: "button", class: XBTN, data: { action: "click->drawer#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
      end

      # ── Footer ────────────────────────────────────────────────────────────────

      def drawer_footer
        div(class: "sticky bottom-0 bg-white border-t border-gray-100 px-6 py-4 flex items-center gap-3") do
          render UI::Button.new(variant: :primary, type: "submit", form: "edit-roles-form") do
            render UI::Icon.new(:paper_plane, class: ICON_SM)
            plain "Request role change"
          end
          button(type: "button", class: "text-[12.5px] font-medium #{LINK_MUTED}",
                 data: { action: "click->drawer#close" }) do
            plain "Cancel"
          end
        end
      end

      # ── Notice + warning ──────────────────────────────────────────────────────

      def effect_notice
        render UI::Notice.new(
          variant:  :warning,
          title:    "Requires a second approver",
          body:     "Role changes are not applied immediately. A member with team management access must approve this request before any permissions change."
        )
      end

      def no_role_warning
        div(class: "no-role-warn items-center gap-3 rounded-xl px-4 py-3",
            style: "background:rgba(220,38,38,0.05);border:1px solid rgba(220,38,38,0.18)") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0 text-red-500") do
            render UI::Icon.new(:alert_circle, class: "w-full h-full")
          end
          p(class: "text-[12px] font-medium", style: "color:var(--ink)") do
            plain "No role selected — this user will have no portal access after saving."
          end
        end
      end

      # ── Role card ─────────────────────────────────────────────────────────────

      def role_card(role)
        meta       = ROLE_META[role.key] || { icon: :key, palette: "brand" }
        checked    = @current_keys.include?(role.key)
        perm_count = role.permissions.size

        label(class: "role-opt flex items-center gap-3 px-4 py-[13px] rounded-xl border border-gray-200 cursor-pointer") do
          input(type: "checkbox", name: "role_keys[]", value: role.key,
                checked: checked, class: "sr-only")

          div(class: "role-chk-box flex-shrink-0 w-[18px] h-[18px] rounded-[5px] border-2 border-gray-300 " \
                     "flex items-center justify-center transition-colors") do
            span(class: "role-chk-icon w-[10px] h-[10px] text-white") do
              render UI::Icon.new(:check, class: "w-full h-full")
            end
          end

          div(class: "w-8 h-8 rounded-[10px] flex items-center justify-center flex-shrink-0 icon-#{meta[:palette]}") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(meta[:icon], class: "w-full h-full") }
          end

          div(class: "flex-1 min-w-0") do
            div(class: "flex items-center gap-2 mb-[2px]") do
              p(class: "text-[13px] font-semibold leading-tight", style: "color:var(--ink)") do
                plain role.name
              end
              if perm_count > 0
                span(class: "badge-gray text-[9.5px] font-bold px-[6px] py-[2px] rounded-full leading-tight flex-shrink-0") do
                  plain "#{perm_count} perms"
                end
              end
            end
            p(class: "text-[11.5px] leading-[1.4]", style: "color:var(--muted-text)") do
              plain role.description.to_s
            end
          end
        end
      end
    end
  end
end
