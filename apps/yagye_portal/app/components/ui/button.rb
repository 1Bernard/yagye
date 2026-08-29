# frozen_string_literal: true

module UI
  class Button < ApplicationComponent
    include UI::Theme

    VARIANTS = {
      primary:   BTN_PRIMARY,
      secondary: BTN_SECONDARY,
      danger:    BTN_DANGER,
      ghost:     BTN_GHOST,
      icon:      BTN_ICON
    }.freeze

    def initialize(variant: :primary, href: nil, **attrs)
      @variant = variant
      @href    = href
      @attrs   = attrs
    end

    def view_template(&)
      base = { class: VARIANTS.fetch(@variant, BTN_SECONDARY) }
      if @href
        a(**mix(base, { href: @href }, @attrs), &)
      else
        button(**mix(base, { type: "button" }, @attrs), &)
      end
    end
  end
end
