# frozen_string_literal: true

module UI
  class Avatar < ApplicationComponent
    include UI::Theme

    SIZES = {
      xs: "w-6 h-6 text-[9px]",
      sm: "w-7 h-7 text-[10px]",
      md: "w-8 h-8 text-[11px]",
      lg: "w-10 h-10 text-xs"
    }.freeze

    PALETTE = [
      "bg-blue-50 text-blue-700",
      "bg-amber-50 text-amber-700",
      "bg-green-50 text-green-700",
      "bg-violet-50 text-violet-700",
      "bg-red-50 text-red-600"
    ].freeze

    def initialize(initials, size: :md, palette_index: nil, **attrs)
      @initials      = initials
      @size          = size
      @palette_index = palette_index
      @attrs         = attrs
    end

    def view_template
      span(**mix({ class: "#{tint} #{SIZES.fetch(@size, SIZES[:md])}" }, @attrs)) do
        plain @initials
      end
    end

    private

    def tint
      base = "rounded-full grid place-items-center font-semibold"
      color = @palette_index.nil? ? AVATAR : PALETTE[@palette_index % PALETTE.size]
      "#{base} #{color}"
    end
  end
end
