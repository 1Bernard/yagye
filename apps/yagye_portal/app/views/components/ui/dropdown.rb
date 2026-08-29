# frozen_string_literal: true

module UI
  # Dropdown menu — trigger + floating panel, wired to dropdown_controller.js.
  # The panel's position classes must be set by the caller via `menu_class:`.
  #
  # Usage:
  #   render UI::Dropdown.new do |d|
  #     d.trigger { render UI::Button.new(variant: :ghost) { "Actions" } }
  #     d.item("View", href: payment_path(@payment))
  #     d.item("Export") { "Export" }
  #     d.separator
  #     d.item("Delete", danger: true) { "Delete" }
  #   end
  class Dropdown < ApplicationComponent
    include UI::Theme

    def initialize(menu_class: "top-full mt-1 right-0")
      @menu_class   = menu_class
      @trigger_block = nil
      @items        = []
    end

    def trigger(&block)
      @trigger_block = block
      nil
    end

    def item(label = nil, href: nil, danger: false, &block)
      @items << { label: label, href: href, danger: danger, block: block }
      nil
    end

    def separator
      @items << { separator: true }
      nil
    end

    def view_template(&block)
      vanish(&block) if block

      div(class: "relative inline-block", data_controller: "dropdown") do
        if @trigger_block
          div(data: { action: "click->dropdown#toggle" }) { @trigger_block.call }
        end
        div(class: "#{DROPDOWN_MENU} #{@menu_class}", data_dropdown_target: "menu") do
          @items.each { |item| render_item(item) }
        end
      end
    end

    private

    def render_item(item)
      return div(class: DROPDOWN_SEP) if item[:separator]

      cls = item[:danger] ? DROPDOWN_ITEM_DANGER : DROPDOWN_ITEM

      if item[:href]
        a(href: item[:href], class: cls) { item[:block] ? item[:block].call : plain(item[:label].to_s) }
      else
        button(type: "button", class: cls) { item[:block] ? item[:block].call : plain(item[:label].to_s) }
      end
    end
  end
end
