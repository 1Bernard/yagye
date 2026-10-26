# frozen_string_literal: true

module UI
  module Filter
    # Chip selection group with soft borders and crisp active states.
    # Supports optional semantic status dots (Emerald, Amber, Rose, Purple, Slate).
    # Guarantees active text remains white on hover without reverting to black.
    class ChipGroup < ApplicationComponent
      include UI::Theme

      STATUS_DOTS = {
        "paid"         => "bg-emerald-500",
        "completed"    => "bg-emerald-500",
        "approved"     => "bg-emerald-500",
        "processing"   => "bg-amber-500",
        "pending"      => "bg-amber-500",
        "submitted"    => "bg-amber-500",
        "under_review" => "bg-blue-500",
        "failed"       => "bg-rose-500",
        "rejected"     => "bg-rose-500",
        "refunded"     => "bg-slate-400",
        "disputed"     => "bg-purple-500"
      }.freeze

      def initialize(name:, options:, selected: nil, type: :radio, status_dots: false, data: {})
        @name        = name
        @options     = options
        @selected    = selected.to_s
        @type        = type
        @status_dots = status_dots
        @data        = data
      end

      def view_template
        div(class: "flex flex-wrap gap-1.5") do
          @options.each do |(lbl, val)|
            is_checked = (val.to_s == @selected) || (val.to_s == "" && @selected.blank?)
            dot_color  = @status_dots ? STATUS_DOTS[val.to_s] : nil

            label(class: "cursor-pointer") do
              input(type: @type.to_s, name: @name, value: val,
                    checked: is_checked,
                    class: "sr-only peer",
                    data: @data)
              span(class: "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-gray-200/80 " \
                          "text-[12px] font-medium text-gray-600 bg-white hover:border-gray-300 " \
                          "hover:text-gray-900 transition-all select-none cursor-pointer " \
                          "peer-checked:bg-gray-900 peer-checked:border-gray-900 peer-checked:text-white " \
                          "peer-checked:hover:text-white peer-checked:hover:bg-gray-800 peer-checked:hover:border-gray-800 " \
                          "peer-checked:shadow-xs") do
                if dot_color
                  span(class: "w-1.5 h-1.5 rounded-full #{dot_color} peer-checked:bg-white flex-shrink-0 transition-colors")
                end
                plain lbl
              end
            end
          end
        end
      end
    end
  end
end
