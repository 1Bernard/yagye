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
        label  = urgent ? "Account not verified" : "Verification in progress"
        detail = "Next: #{step.label} · #{@progress.completed_count} of #{@progress.total_count} steps done"
        cta    = urgent ? "Start verification" : "Continue"

        div(
          class: "w-full px-4 sm:px-6 py-2 flex items-center justify-between gap-4",
          style: "background: #{bg}; border-bottom: 1px solid #{accent}30; min-height: 36px"
        ) do
          div(class: "flex items-center gap-2.5 min-w-0") do
            div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0",
                style: "background: #{accent}")
            span(class: "text-xs font-semibold flex-shrink-0",
                 style: "color: #{accent}") { plain label }
            span(class: "text-xs hidden sm:inline flex-shrink-0",
                 style: "color: #{MUTED}") { plain "—" }
            span(class: "text-xs truncate hidden sm:inline",
                 style: "color: #{MUTED}") { plain detail }
          end

          a(
            href:  verify_step_path(step.key),
            class: "flex-shrink-0 text-xs font-semibold px-3 py-1 rounded-md text-white whitespace-nowrap",
            style: "background: #{BRAND}"
          ) { plain cta }
        end
      end
    end
  end
end
