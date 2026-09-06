# frozen_string_literal: true

module UI
  # Styled toggle switch backed by a native checkbox.
  # Brand-coloured when checked, gray when unchecked.
  #
  #   render UI::Toggle.new(name: "notifications[email]", checked: true)
  class Toggle < ApplicationComponent
    include UI::Theme

    def initialize(name:, checked: false, disabled: false, href: nil, **attrs)
      @name     = name
      @checked  = checked
      @disabled = disabled
      @href     = href
      @attrs    = attrs
    end

    def view_template
      bg      = @checked ? BRAND : BORDER_MED
      wrapper = "relative block #{'opacity-50 pointer-events-none' if @disabled}"

      if @href
        a(href: @href, class: "#{wrapper} cursor-pointer", **@attrs) { track(bg) }
      else
        label(class: "#{wrapper} cursor-pointer", **@attrs) do
          input(type: "checkbox", name: @name, class: "sr-only",
                checked: @checked, disabled: @disabled)
          track(bg)
        end
      end
    end

    private

    def track(bg)
      div(class: "w-9 h-5 rounded-full relative transition-[background] duration-150",
          style: "background:#{bg}") do
        div(class: "absolute top-[2px] w-4 h-4 rounded-full bg-white shadow-sm transition-[left] duration-150",
            style: "left:#{@checked ? '18px' : '2px'}")
      end
    end
  end
end
