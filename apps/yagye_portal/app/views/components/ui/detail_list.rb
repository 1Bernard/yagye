# frozen_string_literal: true

module UI
  # Renders a bordered key-value list — the standard "detail card body" pattern.
  # Usage:
  #   render UI::DetailList.new do |list|
  #     list.row("Label", "value")
  #     list.row("Mono",  "ABC123", mono: true)
  #     list.row("Badge") { render UI::StatusBadge.new(status: "active") }
  #   end
  class DetailList < ApplicationComponent
    include UI::Theme

    def view_template(&block)
      div { yield_content(&block) }
    end

    def row(label, value = nil, mono: false, &block)
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:14px 24px;border-bottom:1px solid #{BORDER}") do
        span(class: TYPE_CAPTION) { label }
        if block
          yield_content(&block)
        else
          span(class: (mono ? TYPE_MONO : TYPE_BODY_MD)) { value.to_s }
        end
      end
    end
  end
end
