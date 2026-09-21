# frozen_string_literal: true

module Onboarding
  class VerifyView < ApplicationComponent
    include UI::Theme

    def initialize(step:, progress:)
      @step     = step
      @progress = progress
    end

    def view_template
      div(class: "min-h-screen", style: "background: #{colors[:surface_subtle]}") do
        div(class: "bg-white border-b px-4 sm:px-8 py-4 flex items-center justify-between",
            style: "border-color: #{colors[:border]}") do
          span(class: "text-sm font-semibold", style: "color: #{colors[:text_primary]}") do
            plain "Business Verification"
          end
          span(class: "text-xs", style: "color: #{colors[:text_muted]}") do
            plain "Step #{@progress.steps.index(@progress.current_step).to_i + 1} of #{@progress.total_count}"
          end
        end

        div(class: "max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8") do
          div(class: "flex gap-8 items-start") do
            step_sidebar
            step_content_panel
          end
        end
      end
    end

    private

    def step_sidebar
      div(class: "hidden lg:block w-72 flex-shrink-0") do
        div(class: "rounded-xl border sticky top-24 overflow-hidden",
            style: "background: #{colors[:surface]}; border-color: #{colors[:border]}") do
          sidebar_header
          div(class: "p-2") do
            @progress.steps.each_with_index do |s, idx|
              step_row(s, idx + 1)
            end
          end
          sidebar_footer
        end
      end
    end

    def sidebar_header
      div(class: "px-5 py-4 border-b", style: "border-color: #{colors[:border]}") do
        div(class: "flex items-center justify-between mb-3") do
          span(class: "text-xs font-semibold uppercase tracking-wide",
               style: "color: #{colors[:text_muted]}") { "Verification Progress" }
          span(class: "text-xs font-medium",
               style: "color: #{colors[:text_secondary]}") do
            "#{@progress.completed_count}/#{@progress.total_count} steps"
          end
        end
        progress_bar
      end
    end

    def progress_bar
      div(class: "w-full rounded-full h-1.5",
          style: "background: #{colors[:border]}") do
        div(class: "h-1.5 rounded-full transition-all duration-500",
            style: "width: #{@progress.percent}%; background: #{colors[:brand_primary]}")
      end
    end

    def step_row(s, number)
      is_active = s.key == @step
      is_done   = s.complete

      link_to(verify_step_path(s.key), class: "flex items-center gap-3 px-3 py-2.5 rounded-lg mb-0.5 group transition-colors #{is_active ? 'active-step' : ''}",
              style: step_row_style(is_active)) do
        step_icon_badge(number, is_done, is_active)
        div do
          p(class: "text-sm font-medium leading-tight",
            style: "color: #{is_active ? colors[:brand_primary] : colors[:text_primary]}") { s.label }
          p(class: "text-xs mt-0.5",
            style: "color: #{colors[:text_muted]}") { s.description }
        end
      end
    end

    def step_row_style(is_active)
      if is_active
        "background: #{colors[:brand_subtle]};"
      else
        ""
      end
    end

    def step_icon_badge(number, done, active)
      bg = done  ? colors[:brand_primary] :
           active ? colors[:brand_primary] :
                    colors[:border]
      color = (done || active) ? "#ffffff" : colors[:text_muted]

      div(class: "flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs font-semibold",
          style: "background: #{bg}; color: #{color}") do
        if done
          svg_check_icon
        else
          plain number.to_s
        end
      end
    end

    def svg_check_icon
      render UI::Icon.new(:check, class: "w-4 h-4")
    end

    def sidebar_footer
      if @progress.all_complete?
        div(class: "px-5 py-4 border-t", style: "border-color: #{colors[:border]}") do
          div(class: "rounded-lg px-3 py-2 text-sm text-center font-medium",
              style: "background: #{colors[:success_subtle]}; color: #{colors[:success]}") do
            "Submitted for review"
          end
        end
      end
    end

    def step_content_panel
      div(class: "flex-1 min-w-0") do
        div(class: "rounded-xl border",
            style: "background: #{colors[:surface]}; border-color: #{colors[:border]}") do
          render step_view_class.new(progress: @progress)
        end
      end
    end

    def step_view_class
      case @step
      when "profile"    then Onboarding::Steps::ProfileStep
      when "contact"    then Onboarding::Steps::ContactStep
      when "settlement" then Onboarding::Steps::SettlementStep
      when "documents"  then Onboarding::Steps::DocumentsStep
      when "agreement"  then Onboarding::Steps::AgreementStep
      end
    end
  end
end
