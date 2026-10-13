# frozen_string_literal: true

module Shared
  # Lazy Turbo Frame banner rendered by Onboarding::VerifyController#banner.
  # Visual treatment mirrors the VerificationPanel settings card rows.
  class KybBanner < ApplicationComponent
    include UI::Theme

    BRAND = UI::Theme::BRAND
    AMBER = UI::Theme::AMBER

    # Matches tier_config() in Settings::VerificationPanel exactly
    URGENT_STYLE = {
      accent:       "#d97706",
      bg:           "rgba(217,119,6,0.07)",
      border:       "rgba(217,119,6,0.22)",
      icon_bg:      "rgba(217,119,6,0.08)",
      icon_border:  "rgba(217,119,6,0.20)"
    }.freeze

    PROGRESS_STYLE = {
      accent:       "#3D47F5",
      bg:           "rgba(61,71,245,0.06)",
      border:       "rgba(61,71,245,0.18)",
      icon_bg:      "rgba(61,71,245,0.08)",
      icon_border:  "rgba(61,71,245,0.20)"
    }.freeze

    REJECTED_STYLE = {
      accent:       "#dc2626",
      bg:           "rgba(220,38,38,0.06)",
      border:       "rgba(220,38,38,0.25)",
      icon_bg:      "rgba(220,38,38,0.08)",
      icon_border:  "rgba(220,38,38,0.22)"
    }.freeze

    def initialize(progress:)
      @progress = progress
    end

    def view_template
      return if @progress.all_complete? && !@progress.rejected?

      turbo_frame_tag("kyb-banner") do
        if @progress.rejected?
          rejected_banner
        else
          progress_banner
        end
      end
    end

    private

    def rejected_banner
      cfg = REJECTED_STYLE

      div(
        class: "w-full border-b kyb-banner-reveal",
        style: "background: #{cfg[:bg]}; border-color: #{cfg[:border]}"
      ) do
        div(style: "display:flex;align-items:center;gap:12px;padding:9px 24px") do
          div(
            class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background: #{cfg[:icon_bg]}; border: 1px solid #{cfg[:icon_border]}"
          ) do
            span(class: "flex w-[14px] h-[14px]", style: "color: #{cfg[:accent]}") do
              render UI::Icon.new(:alert_circle, class: "w-full h-full")
            end
          end

          div(class: "flex-1 min-w-0 flex items-baseline gap-2 flex-wrap") do
            span(
              class: "text-[13px] font-semibold flex-shrink-0",
              style: "color: #{cfg[:accent]}"
            ) { plain "Application not approved" }
            span(class: "#{TYPE_CAPTION} truncate hidden sm:inline") do
              plain "·  Review the feedback and resubmit your application"
            end
          end

          a(
            href:  verify_step_path("agreement"),
            class: "flex-shrink-0 text-white font-medium rounded-[8px] text-[12.5px] " \
                   "px-3 py-[5px] transition-opacity hover:opacity-90 whitespace-nowrap cursor-pointer",
            style: "background: #{cfg[:accent]}",
            data:  { turbo_frame: "_top" }
          ) { plain "Review feedback" }
        end
      end
    end

    def progress_banner
      urgent = @progress.completed_count.zero?
      step   = @progress.current_step
      cfg    = urgent ? URGENT_STYLE : PROGRESS_STYLE
      label  = "Test mode"
      detail = urgent \
        ? "Simulation only — complete KYB to accept live payments" \
        : "Simulation only — #{@progress.completed_count} of #{@progress.total_count} KYB steps done"
      icon   = urgent ? :lock : :shield
      cta    = urgent ? "Complete KYB" : "Continue"

      div(
        class: "w-full border-b kyb-banner-reveal",
        style: "background: #{cfg[:bg]}; border-color: #{cfg[:border]}"
      ) do
        div(style: "display:flex;align-items:center;gap:12px;padding:9px 24px") do
          div(
            class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background: #{cfg[:icon_bg]}; border: 1px solid #{cfg[:icon_border]}"
          ) do
            span(class: "flex w-[14px] h-[14px]", style: "color: #{cfg[:accent]}") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end

          div(class: "flex-1 min-w-0 flex items-baseline gap-2 flex-wrap") do
            span(
              class: "text-[13px] font-semibold flex-shrink-0",
              style: "color: #{cfg[:accent]}"
            ) { plain label }
            span(
              class: "#{TYPE_CAPTION} truncate hidden sm:inline"
            ) { plain "·  #{detail}" }
          end

          div(class: "hidden sm:flex items-center gap-[3px] flex-shrink-0") do
            @progress.steps.each do |s|
              div(
                class: "w-3 h-[3px] rounded-full",
                style: "background: #{s.complete ? cfg[:accent] : 'rgba(156,163,175,0.5)'}"
              )
            end
          end

          a(
            href:  verify_step_path(step.key),
            class: "flex-shrink-0 text-white font-medium rounded-[8px] text-[12.5px] " \
                   "px-3 py-[5px] transition-opacity hover:opacity-90 whitespace-nowrap cursor-pointer",
            style: "background: #{cfg[:accent]}",
            data:  { turbo_frame: "_top" }
          ) { plain cta }
        end
      end
    end
  end
end
