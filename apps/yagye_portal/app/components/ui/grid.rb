# frozen_string_literal: true

module UI
  class Grid < ApplicationComponent
    COLUMNS = {
      2 => "grid grid-cols-1 md:grid-cols-2 gap-5 mb-6",
      3 => "grid grid-cols-1 md:grid-cols-3 gap-5 mb-6",
      4 => "grid grid-cols-2 xl:grid-cols-4 gap-5 mb-6"
    }.freeze

    def initialize(columns: 2)
      @columns = columns
    end

    def view_template(&)
      div(class: COLUMNS.fetch(@columns, COLUMNS[2]), &)
    end
  end
end
