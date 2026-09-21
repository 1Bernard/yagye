# frozen_string_literal: true

module UI
  # Generic pill badge — shared visual shape for any categorization chip.
  # Use this directly when the label and colors are known at the call site.
  # For lifecycle states, use UI::StatusBadge which wraps this with STATUS_MAP lookup.
  class Chip < ApplicationComponent
    def initialize(label:, colors: "bg-gray-100 text-gray-500")
      @label  = label
      @colors = colors
    end

    def view_template
      span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-[11px] font-medium #{@colors}") do
        plain @label
      end
    end
  end
end
