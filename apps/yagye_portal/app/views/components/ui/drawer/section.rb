# frozen_string_literal: true

module UI
  class Drawer
    # Standardized drawer section with disciplined 20px (py-5) vertical rhythm,
    # 24px (px-6) horizontal alignment, and strict TYPE_HEADING typography.
    class Section < ApplicationComponent
      include UI::Theme

      def initialize(title:, icon: nil, palette: "brand", hint: nil, border: true, class_name: nil)
        @title      = title
        @icon       = icon
        @palette    = palette
        @hint       = hint
        @border     = border
        @class_name = class_name
      end

      def view_template(&block)
        border_cls = @border ? "border-b border-gray-100" : ""
        div(class: "px-6 py-5 #{border_cls} #{@class_name}".strip) do
          div(class: "flex items-center gap-2 mb-3") do
            if @icon
              div(class: "w-5 h-5 rounded-md flex items-center justify-center flex-shrink-0 icon-#{@palette}") do
                span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(@icon, class: "w-full h-full") }
              end
            end
            p(class: TYPE_HEADING) { plain @title }
          end

          p(class: "#{TYPE_CAPTION} -mt-1.5 mb-3") { plain @hint } if @hint.present?

          div(&block) if block
        end
      end
    end
  end
end
