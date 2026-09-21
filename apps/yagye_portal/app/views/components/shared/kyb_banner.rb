# frozen_string_literal: true

module Shared
  # Rendered inside the turbo-frame[id="kyb-banner"] that Layout::Shell injects
  # for merchant users. Called by Onboarding::VerifyController#banner.
  # Uses UI::Theme constants directly because Phlex's rendering context proxies
  # helper methods but does not always surface included-module instance methods
  # in private helper calls.
  class KybBanner < ApplicationComponent
    BRAND    = UI::Theme::BRAND
    TINT     = UI::Theme::TINT_BRAND
    AMBER    = UI::Theme::AMBER
    TINT_AMB = UI::Theme::TINT_AMBER
    MUTED    = UI::Theme::MUTED_TEXT

    def initialize(progress:)
      @progress = progress
    end

    def view_template
      return if @progress.all_complete?

      turbo_frame_tag("kyb-banner") do
        urgent = @progress.completed_count.zero?
        step   = @progress.current_step
        accent = urgent ? AMBER : BRAND
        bg     = urgent ? TINT_AMB : TINT

        div(
          class: "w-full px-4 py-2.5 flex items-center justify-between gap-4 text-sm",
          style: "background: #{bg}; border-bottom: 1px solid #{accent}20"
        ) do
          div(class: "flex items-center gap-3 min-w-0") do
            div(class: "flex-shrink-0 w-2 h-2 rounded-full",
                style: "background: #{accent}")
            span(class: "font-medium truncate", style: "color: #{accent}") do
              plain step.label
            end
            span(class: "text-xs hidden sm:inline", style: "color: #{MUTED}") do
              plain "#{@progress.percent}% complete · #{@progress.completed_count}/#{@progress.total_count} steps"
            end
          end

          div(class: "flex items-center gap-3 flex-shrink-0") do
            a(
              href:  verify_step_path(step.key),
              class: "inline-flex items-center px-3 py-1 rounded-md text-xs font-semibold whitespace-nowrap text-white",
              style: "background: #{BRAND}"
            ) { plain "Continue →" }
          end
        end
      end
    end
  end
end
