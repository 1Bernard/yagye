# frozen_string_literal: true

module UI
  class Badge < ApplicationComponent
    include UI::Theme

    VARIANTS = {
      success: BADGE_SUCCESS,
      pending: BADGE_PENDING,
      failed:  BADGE_FAILED,
      warning: BADGE_WARNING,
      info:    BADGE_INFO,
      neutral: BADGE_NEUTRAL
    }.freeze

    DOTS = {
      success: "bg-green-500",
      pending: "bg-violet-500",
      failed:  "bg-red-500",
      warning: "bg-amber-500",
      info:    "bg-blue-500",
      neutral: "bg-gray-400"
    }.freeze

    def initialize(variant: :neutral)
      @variant = variant
    end

    def render?
      VARIANTS.key?(@variant)
    end

    def view_template(&block)
      span(class: VARIANTS[@variant]) do
        span(class: "w-1.5 h-1.5 rounded-full #{DOTS[@variant]}")
        yield if block
      end
    end
  end
end
