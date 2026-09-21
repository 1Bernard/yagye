# frozen_string_literal: true

module Shared
  # Lazy-loaded KYB progress banner — rendered inside a Turbo Frame by
  # Onboarding::VerifyController#banner (GET /onboarding/kyb-banner).
  # Layout::Shell embeds <turbo-frame id="kyb-banner" src=...> for merchant users;
  # this component fills it if KYB is still incomplete.
  class KybBanner < ApplicationComponent
    include UI::Theme

    def initialize(progress:)
      @progress = progress
    end

    def view_template
      turbo_frame_tag("kyb-banner") do
        return if @progress.all_complete?

        urgent = @progress.completed_count.zero?
        step   = @progress.current_step

        div(
          class: "relative w-full px-4 py-2.5 flex items-center justify-between gap-4 text-sm",
          style: banner_style(urgent)
        ) do
          left_content(step, urgent)
          right_content(step)
          dismiss_button
        end
      end
    end

    private

    def banner_style(urgent)
      bg    = urgent ? colors[:warning_subtle] : colors[:brand_subtle]
      color = urgent ? colors[:warning]        : colors[:brand_primary]
      "background: #{bg}; border-bottom: 1px solid #{color}20;"
    end

    def left_content(step, urgent)
      accent = urgent ? colors[:warning] : colors[:brand_primary]
      div(class: "flex items-center gap-3 min-w-0") do
        div(class: "flex-shrink-0 w-2 h-2 rounded-full", style: "background: #{accent}")
        span(class: "font-medium truncate", style: "color: #{accent}") do
          plain step.label
        end
        span(class: "text-xs hidden sm:inline", style: "color: #{colors[:text_muted]}") do
          plain "#{@progress.percent}% complete · #{@progress.completed_count}/#{@progress.total_count} steps"
        end
      end
    end

    def right_content(step)
      a(
        href:  verify_step_path(step.key),
        class: "flex-shrink-0 inline-flex items-center px-3 py-1 rounded-md text-xs font-semibold whitespace-nowrap",
        style: "background: #{colors[:brand_primary]}; color: #ffffff"
      ) { plain "Continue →" }
    end

    def dismiss_button
      button(
        type:       "button",
        class:      "flex-shrink-0 ml-1 p-0.5 rounded opacity-60 hover:opacity-100 transition-opacity",
        style:      "color: #{colors[:text_muted]}",
        data:       { action: "click->kyb-banner#dismiss" },
        aria_label: "Dismiss"
      ) do
        render UI::Icon.new(:x, class: "w-4 h-4")
      end
    end
  end
end
