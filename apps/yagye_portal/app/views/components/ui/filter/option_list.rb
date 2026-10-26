# frozen_string_literal: true

module UI
  module Filter
    # Selectable option list with support for rich interactive cards (matching Team::Users::InviteView).
    # Provides icon badges, clear typography, and active border/fill states with checkmarks.
    class OptionList < ApplicationComponent
      include UI::Theme

      def initialize(name:, options:, selected: nil, type: :radio, icon_palette: "purple",
                     variant: :cards, data: {})
        @name         = name
        @options      = options
        @selected     = selected.to_s
        @type         = type
        @icon_palette = icon_palette
        @variant      = variant
        @data         = data
      end

      def view_template
        if @variant == :cards
          cards_template
        else
          compact_template
        end
      end

      private

      def cards_template
        div(class: "flex flex-col gap-2") do
          @options.each do |option|
            lbl, val, icon, hint = option
            is_checked = (val.to_s == @selected) || (val.to_s == "" && @selected.blank?)

            label(class: "group flex items-center gap-3 px-3.5 py-2.5 rounded-xl border border-gray-200 " \
                         "cursor-pointer transition-all hover:border-gray-300 hover:bg-gray-50/70 " \
                         "has-[:checked]:border-[#3D47F5] has-[:checked]:bg-[rgba(61,71,245,0.04)]") do
              input(type: @type.to_s, name: @name, value: val,
                    checked: is_checked,
                    class: "sr-only peer",
                    data: @data)
              if icon
                div(class: "w-7 h-7 rounded-[8px] flex items-center justify-center flex-shrink-0 icon-#{@icon_palette}") do
                  span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                end
              end
              div(class: "flex-1 min-w-0") do
                p(class: "text-[13px] font-semibold text-gray-900 leading-tight") { plain lbl }
                p(class: "#{TYPE_CAPTION} text-gray-400 leading-tight mt-0.5 truncate") { plain hint } if hint.present?
              end
              div(class: "w-4 h-4 rounded-full border border-gray-300 flex items-center justify-center ml-auto flex-shrink-0 " \
                         "transition-colors peer-checked:border-[#3D47F5] peer-checked:bg-[#3D47F5]") do
                span(class: "flex w-2.5 h-2.5 text-white opacity-0 peer-checked:opacity-100 transition-opacity") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
              end
            end
          end
        end
      end

      def compact_template
        div(class: "flex flex-col gap-[2px]") do
          @options.each do |(lbl, val, icon)|
            is_checked = (val.to_s == @selected) || (val.to_s == "" && @selected.blank?)

            label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 " \
                        "cursor-pointer transition-colors -mx-2") do
              input(type: @type.to_s, name: @name, value: val,
                    checked: is_checked,
                    class: "w-[13px] h-[13px] accent-[#3D47F5] flex-shrink-0 cursor-pointer",
                    data: @data)
              if icon
                div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{@icon_palette}") do
                  span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
                end
              end
              span(class: TYPE_BODY_MD) { plain lbl }
            end
          end
        end
      end
    end
  end
end
