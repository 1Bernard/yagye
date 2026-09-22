# frozen_string_literal: true

module Onboarding
  class VerifyView < ApplicationComponent
    include UI::Theme

    BRAND = UI::Theme::BRAND

    STEP_ICONS = {
      "profile"    => :building,
      "contact"    => :mail,
      "settlement" => :trending_up,
      "documents"  => :file,
      "agreement"  => :check_circle
    }.freeze

    def initialize(step:, progress:)
      @step     = step
      @progress = progress
    end

    def view_template
      render Layout::Shell.new(
        active_nav:      :settings,
        title:           "Business Verification",
        breadcrumbs:     [{ label: "Settings", href: settings_path }, { label: "Business Verification" }],
        show_kyb_banner: false
      ) do
        div(class: "flex gap-10 items-start") do
          step_sidebar
          div(class: "flex-1 min-w-0") do
            div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
              render step_view_class.new(progress: @progress)
            end
          end
        end
      end
    end

    private

    # ── Connected step tracker ────────────────────────────────────────────────

    def step_sidebar
      div(class: "hidden lg:flex w-[196px] flex-shrink-0 flex-col sticky top-6") do
        sidebar_header
        div(class: "mt-6") do
          @progress.steps.each_with_index do |s, i|
            step_row(s, i + 1, last: i == @progress.total_count - 1)
          end
        end
      end
    end

    def sidebar_header
      div do
        p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-[0.07em] mb-3") do
          plain "Verification"
        end
        div(class: "w-full h-[3px] rounded-full overflow-hidden bg-gray-100") do
          div(
            class: "h-full rounded-full transition-all duration-700",
            style: "width: #{@progress.percent}%; background: #{BRAND}"
          )
        end
        p(class: "#{TYPE_CAPTION} mt-1.5") do
          plain "#{@progress.completed_count} of #{@progress.total_count} steps complete"
        end
      end
    end

    def step_row(s, number, last: false)
      is_active = s.key == @step
      is_done   = s.complete

      div(class: "flex gap-3") do
        # Left column: state circle + connector line
        div(class: "flex flex-col items-center flex-shrink-0 w-6") do
          step_circle(number, is_done, is_active)
          unless last
            div(
              class: "w-px flex-1 mt-1",
              style: "background: #{is_done ? "rgba(61,71,245,0.25)" : "#E5E7EB"}; min-height: 28px"
            )
          end
        end

        # Right column: label + optional description
        div(class: "#{last ? 'pt-[3px]' : 'pb-[28px] pt-[3px]'} flex-1 min-w-0") do
          a(
            href:  verify_step_path(s.key),
            class: "block text-[13px] leading-tight no-underline transition-colors #{step_label_class(is_done, is_active)}",
            style: is_active ? "color: #{BRAND}" : ""
          ) { plain s.label }

          if is_active
            p(class: "#{TYPE_CAPTION} mt-0.5 leading-tight") { plain s.description }
          end
        end
      end
    end

    def step_circle(number, done, active)
      if done
        div(
          class: "w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0",
          style: "background: #{BRAND}"
        ) do
          span(class: "flex w-3 h-3 text-white") do
            render UI::Icon.new(:check, class: "w-full h-full")
          end
        end
      elsif active
        div(
          class: "w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0",
          style: "background: #{BRAND}"
        ) do
          div(style: "width: 8px; height: 8px; border-radius: 50%; background: white")
        end
      else
        div(
          class: "w-6 h-6 rounded-full border-2 border-gray-200 bg-white " \
                 "flex items-center justify-center flex-shrink-0"
        ) do
          span(class: "text-[10px] font-bold text-gray-300") { plain number.to_s }
        end
      end
    end

    def step_label_class(done, active)
      return "font-semibold"            if active
      return "font-medium text-gray-600 hover:text-gray-900" if done
      "font-medium text-gray-400 hover:text-gray-500"
    end

    # ── Step view routing ─────────────────────────────────────────────────────

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
