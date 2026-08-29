# frozen_string_literal: true

module UI
  # Renders a locked button/link that shows a tier-upgrade prompt instead of
  # performing the action. Use when a feature requires a higher merchant tier.
  #
  #   render UI::TierGate.new(required_tier: 2, current_tier: user.merchant_tier) do
  #     "Export CSV"
  #   end
  #
  # If current_tier >= required_tier, the block is rendered as a normal button.
  # Otherwise a locked pill is rendered with a tooltip explaining the requirement.
  class TierGate < ApplicationComponent
    BRAND  = "#3D47F5"
    AMBER  = "#d97706"
    GREEN  = "#16a34a"

    TIER_LABELS = {
      1 => "Tier 1",
      2 => "Tier 2 — Standard",
      3 => "Tier 3 — Verified"
    }.freeze

    TIER_COLORS = {
      1 => AMBER,
      2 => BRAND,
      3 => GREEN
    }.freeze

    def initialize(required_tier:, current_tier:, upgrade_path: nil)
      @required_tier = required_tier
      @current_tier  = current_tier.to_i
      @upgrade_path  = upgrade_path
    end

    def view_template(&block)
      if @current_tier >= @required_tier
        yield
      else
        locked_pill(&block)
      end
    end

    private

    def locked_pill(&block)
      color = TIER_COLORS[@required_tier] || BRAND
      label = TIER_LABELS[@required_tier] || "Tier #{@required_tier}"

      div(style: "position:relative;display:inline-flex;align-items:center;gap:6px") do
        # Dim overlay wrapper
        span(style: "display:inline-flex;align-items:center;gap:6px;opacity:0.45;cursor:not-allowed;pointer-events:none") do
          yield if block
        end

        # Lock badge
        span(style: "display:inline-flex;align-items:center;gap:4px;" \
                    "padding:2px 8px 2px 5px;border-radius:20px;" \
                    "background:rgba(#{hex_to_rgb(color)},0.10);border:1px solid rgba(#{hex_to_rgb(color)},0.20);" \
                    "font-size:10.5px;font-weight:600;color:#{color};white-space:nowrap") do
          span(style: "display:flex;width:11px;height:11px") do
            render UI::Icon.new(:lock, class: "w-full h-full")
          end
          plain "Requires #{label}"
        end

        # CTA link
        if @upgrade_path
          a(href: @upgrade_path,
            style: "font-size:11px;font-weight:600;color:#{color};text-decoration:none;white-space:nowrap") do
            plain "Upgrade →"
          end
        end
      end
    end

    def hex_to_rgb(hex)
      hex = hex.delete("#")
      r = hex[0..1].to_i(16)
      g = hex[2..3].to_i(16)
      b = hex[4..5].to_i(16)
      "#{r},#{g},#{b}"
    end
  end
end
