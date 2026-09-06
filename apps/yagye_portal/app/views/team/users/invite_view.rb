# frozen_string_literal: true

module Team
  module Users
    class InviteView < ApplicationComponent
      include UI::Theme

      def view_template
        turbo_frame_tag "drawer-frame" do
          drawer_header
          div(class: "flex-1 min-h-0 overflow-y-auto") do
            form(action: team_invite_user_path, method: "post", id: "invite-form",
                 class: "px-6 py-5 flex flex-col gap-6") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              contact_section
              role_section
            end
          end
          drawer_footer
        end
      end

      private

      # ── Header ────────────────────────────────────────────────────────────────

      def drawer_header
        div(class: DRAWER_HEAD) do
          div(class: "flex items-center gap-3 min-w-0") do
            div(class: "w-8 h-8 rounded-lg icon-brand flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:users, class: "w-full h-full") }
            end
            div(class: "min-w-0") do
              p(class: TYPE_MICRO) { plain "Team members" }
              p(class: "text-[14px] font-semibold truncate", style: "color:var(--ink)") do
                plain "Invite team member"
              end
            end
          end
          button(type: "button", class: XBTN, data: { action: "click->drawer#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
      end

      # ── Body sections ─────────────────────────────────────────────────────────

      def contact_section
        div do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
            plain "Contact details"
          end
          div(class: "flex flex-col gap-3") do
            div(class: "grid grid-cols-2 gap-3") do
              render UI::InputField.new(name: "first_name", label: "First name", required: true)
              render UI::InputField.new(name: "last_name",  label: "Last name",  required: true)
            end
            render UI::InputField.new(name: "email", label: "Email address", type: "email", required: true)
          end
        end
      end

      def role_section
        div do
          p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-[6px]") do
            plain "Assign a role"
          end
          p(class: "#{TYPE_CAPTION} mb-4") do
            plain "Choose the role that best matches this person's responsibilities."
          end

          div(class: "flex flex-col gap-2") do
            p(class: "#{TYPE_MICRO} text-gray-400 mb-1") { plain "Merchant" }
            Portal::RoleMetadata::MERCHANT.each do |r|
              role_card(r[:label], r[:key], r[:hint], icon: r[:icon], palette: r[:palette])
            end
          end

          div(class: "flex flex-col gap-2 mt-5") do
            p(class: "#{TYPE_MICRO} text-gray-400 mb-1") { plain "Internal" }
            Portal::RoleMetadata::INTERNAL.each do |r|
              role_card(r[:label], r[:key], r[:hint], icon: r[:icon], palette: r[:palette])
            end
          end
        end
      end

      # ── Footer ────────────────────────────────────────────────────────────────

      def drawer_footer
        div(class: "sticky bottom-0 bg-white border-t border-gray-100 px-6 py-4 flex items-center gap-3") do
          render UI::Button.new(variant: :primary, type: "submit", form: "invite-form") do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "Send invitation"
          end
          button(type: "button", class: "text-[12.5px] font-medium #{LINK_MUTED}",
                 data: { action: "click->drawer#close" }) do
            plain "Cancel"
          end
        end
      end

      # ── Role card ─────────────────────────────────────────────────────────────

      def role_card(lbl, val, hint, icon:, palette:)
        card_id = "invite-role-#{val}"
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
          span(class: "flex-shrink-0 flex w-[15px] h-[15px] text-[#3D47F5]") do
            render UI::Icon.new(:check, class: "w-full h-full")
          end
        end
      end
    end
  end
end
