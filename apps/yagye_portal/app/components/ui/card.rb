# frozen_string_literal: true

module UI
  class Card < ApplicationComponent
    include UI::Theme

    def initialize(title: nil, padding: true)
      @title   = title
      @padding = padding
    end

    def view_template(&block)
      div(class: "#{SURFACE_CARD} #{@padding ? 'p-6' : ''} flex flex-col h-full") do
        h2(class: "#{TEXT_H2} mb-4") { @title } if @title
        yield if block
      end
    end
  end
end
