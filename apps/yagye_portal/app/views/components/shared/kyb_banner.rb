# frozen_string_literal: true

module Shared
  # Persistent top-of-page banner shown to merchant users who have not yet
  # completed KYB. Reads merchant_tier from the current user — no API call.
  # Hidden once tier >= 3 (KYB approved).
  class KybBanner < ApplicationComponent
    include UI::Theme

    TIER_MESSAGES = {
      0 => { label: "Account not verified",    cta: "Start verification",  urgent: true },
      1 => { label: "Verification in progress", cta: "Continue setup",     urgent: false },
      2 => { label: "Verification submitted",   cta: "View status",        urgent: false }
    }.freeze

    def initialize(merchant_tier:, percent_complete: nil)
      @merchant_tier    = merchant_tier.to_i
      @percent_complete = percent_complete
    end

    def view_template
      return if @merchant_tier >= 3

      info = TIER_MESSAGES[@merchant_tier] || TIER_MESSAGES[0]

      div(
        id:    "kyb-banner",
        class: "relative w-full px-4 py-2.5 flex items-center justify-between gap-4 text-sm",
        style: banner_style(info[:urgent])
      ) do
        left_content(info)
        right_content(info)
        dismiss_button
      end
    end

    private

    def banner_style(urgent)
      bg    = urgent ? colors[:warning_subtle] : colors[:brand_subtle]
      color = urgent ? colors[:warning]        : colors[:brand_primary]
      "background: #{bg}; border-bottom: 1px solid #{color}20;"
    end

    def left_content(info)
      div(class: "flex items-center gap-3 min-w-0") do
        dot(info[:urgent])
        span(class: "font-medium truncate",
             style: "color: #{info[:urgent] ? colors[:warning] : colors[:brand_primary]}") do
          info[:label]
        end
        if @percent_complete
          span(class: "text-xs hidden sm:inline",
               style: "color: #{colors[:text_muted]}") do
            "#{@percent_complete}% complete"
          end
        end
      end
    end

    def dot(urgent)
      div(class: "flex-shrink-0 w-2 h-2 rounded-full",
          style: "background: #{urgent ? colors[:warning] : colors[:brand_primary]}")
    end

    def right_content(info)
      a(
        href:  verify_path,
        class: "flex-shrink-0 inline-flex items-center px-3 py-1 rounded-md text-xs font-semibold whitespace-nowrap transition-colors",
        style: "background: #{colors[:brand_primary]}; color: #ffffff"
      ) { info[:cta] }
    end

    def dismiss_button
      button(
        type:              "button",
        class:             "flex-shrink-0 ml-1 p-0.5 rounded opacity-60 hover:opacity-100 transition-opacity",
        style:             "color: #{colors[:text_muted]}",
        data:              { action: "click->kyb-banner#dismiss" },
        aria_label:        "Dismiss"
      ) do
        svg(xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24",
            stroke: "currentColor", class: "w-4 h-4") do |s|
          s.path(stroke_linecap: "round", stroke_linejoin: "round", stroke_width: "2",
                 d: "M6 18L18 6M6 6l12 12")
        end
      end
    end
  end
end
