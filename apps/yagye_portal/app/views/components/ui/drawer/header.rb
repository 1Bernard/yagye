# frozen_string_literal: true

module UI
  class Drawer
    # Standardized drawer header with category eyebrow, icon badge, title,
    # optional active count badge, and accessible dismiss button.
    # Matches the high-end fintech aesthetic from Team::Users::InviteView.
    class Header < ApplicationComponent
      include UI::Theme

      def initialize(title:, subtitle: nil, category: nil, icon: :filter, palette: "brand",
                     active_count: nil, close_action: "click->drawer#close")
        @title        = title
        @subtitle     = subtitle
        @category     = category
        @icon         = icon
        @palette      = palette
        @active_count = active_count.to_i
        @close_action = close_action
      end

      def view_template
        div(class: DRAWER_HEAD) do
          div(class: "flex items-center gap-3 min-w-0") do
            if @icon
              div(class: "w-8 h-8 rounded-lg icon-#{@palette} flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(@icon, class: "w-full h-full") }
              end
            end

            div(class: "min-w-0") do
              p(class: TYPE_MICRO) { plain @category } if @category.present?
              div(class: "flex items-center gap-2") do
                p(class: "text-[14px] font-semibold truncate", style: "color:var(--ink)") do
                  plain @title
                end
                if @active_count > 0
                  span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[10px] " \
                             "font-semibold bg-indigo-50 text-indigo-600 border border-indigo-100") do
                    plain "#{@active_count} active"
                  end
                end
              end
              p(class: "#{TYPE_CAPTION} mt-0.5 truncate") { plain @subtitle } if @subtitle.present?
            end
          end

          button(type: "button", class: XBTN,
                 data: { action: @close_action },
                 aria: { label: "Close drawer" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
      end
    end
  end
end
