# frozen_string_literal: true

module UI
  class Grid < ApplicationComponent
    include UI::Theme

    TAILWIND_COLS = {
      2 => "grid grid-cols-1 md:grid-cols-2 gap-5 mb-6",
      3 => "grid grid-cols-1 md:grid-cols-3 gap-5 mb-6",
      4 => "grid grid-cols-2 xl:grid-cols-4 gap-5 mb-6"
    }.freeze

    INLINE_COLS = {
      sidebar:    "display:grid;grid-template-columns:1fr 320px;gap:24px;align-items:start",
      sidebar_lg: "display:grid;grid-template-columns:1fr 340px;gap:24px;align-items:start",
      profile:    "display:grid;grid-template-columns:320px 1fr;gap:24px;align-items:start"
    }.freeze

    def initialize(columns: 2)
      @columns = columns
    end

    def view_template(&block)
      if (inline = INLINE_COLS[@columns])
        div(style: inline, &block)
      else
        div(class: TAILWIND_COLS.fetch(@columns, TAILWIND_COLS[2]), &block)
      end
    end
  end
end
