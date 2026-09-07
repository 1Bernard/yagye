# frozen_string_literal: true

module Team
  module Users
    class FilterView < ApplicationComponent
      include UI::Theme

      def initialize(query: nil, role: nil, status: nil)
        @query  = query
        @role   = role
        @status = status
      end

      def view_template
        turbo_frame_tag "drawer-frame" do
          div(class: DRAWER_HEAD) do
            div do
              p(class: TYPE_TITLE) { plain "Filter members" }
              p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Narrow by status or role." }
            end
            button(type: "button", class: XBTN,
                   data: { action: "click->drawer#close" }) { plain "✕" }
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

      private

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
    end
  end
end
