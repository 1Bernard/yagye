# frozen_string_literal: true

module UI
  # Premium auto-dismissing toast — top-right fixed, dark card with a
  # colored left accent strip, inline icon, progress drain bar.
  # Requires toast_controller.js (Stimulus).
  #
  # All appearance-critical styles use inline CSS so Tailwind scanner gaps
  # cannot break the visual output. Only structural layout classes (flex,
  # fixed, overflow-hidden, etc.) rely on Tailwind.
  class Flash < ApplicationComponent
    include UI::Theme

    TYPES = {
      "notice"  => { icon: :check_circle, color: "#22c55e", icon_color: "#4ade80" },
      "success" => { icon: :check_circle, color: "#22c55e", icon_color: "#4ade80" },
      "alert"   => { icon: :alert_circle, color: "#ef4444", icon_color: "#f87171" },
      "error"   => { icon: :alert_circle, color: "#ef4444", icon_color: "#f87171" },
      "warning" => { icon: :info_circle,  color: "#f59e0b", icon_color: "#fbbf24" },
      "info"    => { icon: :info_circle,  color: "#3b82f6", icon_color: "#60a5fa" }
    }.freeze

    STACK_STYLE = "position:fixed;top:20px;right:20px;z-index:9000;" \
                  "display:flex;flex-direction:column;gap:10px;align-items:flex-end;" \
                  "pointer-events:none"

    CARD_STYLE  = "pointer-events:auto;position:relative;overflow:hidden;" \
                  "display:flex;align-items:flex-start;gap:12px;" \
                  "width:356px;padding:16px 16px 16px 20px;" \
                  "background:#0F0F10;border:1px solid rgba(255,255,255,0.07);" \
                  "border-radius:16px;opacity:0;transform:translateY(-8px);" \
                  "transition:opacity 300ms ease-out,transform 300ms ease-out;" \
                  "box-shadow:0 4px 6px rgba(0,0,0,0.25),0 20px 48px rgba(0,0,0,0.55)," \
                  "0 0 0 1px rgba(255,255,255,0.03)"

    def initialize(flash:)
      @flash = flash
    end

    def render?
      @flash.present? && @flash.any?
    end

    def view_template
      div(style: STACK_STYLE) do
        @flash.each do |type, message|
          next if message.blank?
          toast(type.to_s, message.to_s)
        end
      end
    end

    private

    def toast(type, message)
      meta  = TYPES.fetch(type, TYPES["info"])
      color = meta[:color]

      div(style: CARD_STYLE, data: { controller: "toast" }) do
        # Left accent strip
        span(style: "position:absolute;inset:0 auto 0 0;width:3px;" \
                    "border-radius:16px 0 0 16px;background:#{color}")

        # Icon — colored via inline style on the SVG wrapper
        span(style: "color:#{meta[:icon_color]};flex-shrink:0;margin-top:1px;" \
                    "width:18px;height:18px;display:flex;align-items:center;justify-content:center") do
          render UI::Icon.new(meta[:icon], class: "w-full h-full")
        end

        # Message
        span(style: "flex:1;font-size:13.5px;font-weight:500;line-height:1.45;" \
                    "color:rgba(255,255,255,0.88);padding-top:1px") do
          plain message
        end

        # Dismiss ×
        button(
          type: "button",
          class: "toast-dismiss",
          data:  { action: "click->toast#dismiss" }
        ) do
          render UI::Icon.new(:x, class: "w-3.5 h-3.5")
        end

        # Progress drain bar — JS animates scaleX(1→0) over the delay window
        div(style: "position:absolute;bottom:0;left:12px;right:12px;height:2px;" \
                   "border-radius:9999px;overflow:hidden;background:#{color}22") do
          span(style: "display:block;height:100%;border-radius:9999px;" \
                      "background:#{color};transform-origin:left;transform:scaleX(1)",
               data: { toast_target: "progress" })
        end
      end
    end
  end
end
