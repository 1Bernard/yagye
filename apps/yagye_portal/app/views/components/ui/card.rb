# frozen_string_literal: true

module UI
  # Composable card shell. Yields |self| so callers can call the slot methods,
  # which render HTML directly into the output buffer via yield_content.
  #
  # Full usage:
  #   render UI::Card.new do |c|
  #     c.header("Payment details", icon: :credit_card) { render UI::Button.new(...) }
  #     c.body { render UI::DetailList.new { ... } }
  #     c.footer { pagination_row }
  #   end
  #
  # Padded body shorthand:
  #   render UI::Card.new do |c|
  #     c.header("Summary")
  #     c.body(padding: true) { p(class: TYPE_CAPTION) { plain "…" } }
  #   end
  class Card < ApplicationComponent
    include UI::Theme

    def view_template(&block)
      div(class: "#{SURFACE_CARD} flex flex-col overflow-hidden") do
        yield_content(&block)
      end
    end

    # ── Slots ─────────────────────────────────────────────────────────────────

    # Renders a standard card header row with optional icon and action block.
    def header(title, icon: nil, &action)
      div(class: "flex items-center justify-between px-[22px] py-4 border-b border-gray-100") do
        div(class: "flex items-center gap-[10px]") do
          if icon
            span(class: "flex w-[14px] h-[14px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          p(class: TYPE_TITLE) { plain title }
        end
        yield_content(&action) if action
      end
    end

    # Renders a card body. padding: true wraps content in px-6 py-5; padding: false renders directly.
    def body(padding: true, &block)
      if padding
        div(class: "px-6 py-5") { yield_content(&block) }
      else
        yield_content(&block)
      end
    end

    # Renders a card footer row with a top border.
    def footer(&block)
      div(class: "flex items-center justify-between px-5 py-3 border-t border-gray-100") do
        yield_content(&block)
      end
    end
  end
end
