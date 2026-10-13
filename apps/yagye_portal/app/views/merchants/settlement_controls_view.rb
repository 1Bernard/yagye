# frozen_string_literal: true

module Merchants
  class SettlementControlsView < ApplicationComponent
    include UI::Theme

    WEEKDAYS = [
      [ "Monday",    "1" ], [ "Tuesday", "2" ], [ "Wednesday", "3" ],
      [ "Thursday",  "4" ], [ "Friday",  "5" ]
    ].freeze

    MONTH_DAYS = (1..28).map { |d| [ "#{d.ordinalize} of the month", d.to_s ] }.freeze

    def initialize(application:, controls: {}, staff: [])
      @app      = application
      @controls = controls
      @staff    = staff
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      "Settlement Controls",
        breadcrumbs: [
          { label: "Merchants",        url: merchants_path },
          { label: @app.legal_name || @app.merchant_code, url: merchant_path(@app) },
          { label: "Settlement Controls" }
        ]
      ) do
        render UI::Grid.new(columns: :sidebar) do
          left_column
          right_column
        end
      end
    end

    private

    def left_column
      div(class: "flex flex-col gap-5") do
        schedule_card
        controls_card
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        how_it_works_card
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def threshold
      @controls["approval_threshold"]
    end

    def approver_codes
      Array(@controls["approver_user_codes"])
    end

    def frequency
      @controls["settlement_frequency"] || "daily"
    end

    def settlement_day
      @controls["settlement_day"].to_s
    end

    # ── Right column ──────────────────────────────────────────────────────────

    def how_it_works_card
      render UI::Card.new do |c|
        c.header("How it works")
        c.body do
          div(class: "flex flex-col gap-4") do
            info_point(
              :clock,
              "Payout schedule",
              "Controls when settled funds are released to the merchant's bank account — daily, weekly, or monthly."
            )
            info_point(
              :check_circle,
              "Approval threshold",
              "Settlement batches at or above this amount require manual approval before dispatch. " \
              "Leave blank to auto-approve all."
            )
            info_point(
              :users,
              "Approvers",
              "Yagye Ops Managers who can approve large settlement batches on behalf of Yagye."
            )
          end
        end
      end
    end

    def info_point(icon, title, body)
      div(class: "flex items-start gap-3") do
        div(class: "w-7 h-7 rounded-lg bg-indigo-50 flex items-center justify-center flex-shrink-0 mt-[1px]") do
          span(class: "flex w-[13px] h-[13px] text-indigo-500") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight") { plain title }
          p(class: "#{TYPE_CAPTION} mt-[3px] leading-relaxed") { plain body }
        end
      end
    end

    # ── Schedule card ─────────────────────────────────────────────────────────

    def schedule_card
      render UI::Card.new do |c|
        c.header("Payout Schedule")
        c.body(padding: false) do
          form(action: merchant_settlement_controls_path(@app), method: "post",
               data: { turbo: false, controller: "schedule-picker" }) do
            input(type: "hidden", name: "_method",            value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            # Preserve controls settings so "Save schedule" doesn't wipe them
            input(type: "hidden", name: "approval_threshold", value: threshold) if threshold
            approver_codes.each do |code|
              input(type: "hidden", name: "approver_user_codes[]", value: code)
            end

            div(class: "px-6 py-5 flex flex-col gap-5") do
              form_field("Release frequency") do
                select(
                  name:  "settlement_frequency",
                  class: SELECT_FIELD,
                  data:  { action: "change->schedule-picker#toggle",
                           schedule_picker_target: "frequency" }
                ) do
                  option(value: "daily",   selected: frequency == "daily")   { plain "Daily — every business day" }
                  option(value: "weekly",  selected: frequency == "weekly")  { plain "Weekly — pick a day" }
                  option(value: "monthly", selected: frequency == "monthly") { plain "Monthly — pick a date" }
                end
              end

              div(data: { schedule_picker_target: "weekday" },
                  style: frequency == "weekly" ? "" : "display:none") do
                form_field("Day of week") do
                  select(name: "settlement_day_weekly", class: SELECT_FIELD) do
                    WEEKDAYS.each do |(day_name, val)|
                      option(value: val, selected: frequency == "weekly" && settlement_day == val) { plain day_name }
                    end
                  end
                end
              end

              div(data: { schedule_picker_target: "monthday" },
                  style: frequency == "monthly" ? "" : "display:none") do
                form_field("Day of month") do
                  select(name: "settlement_day_monthly", class: SELECT_FIELD) do
                    MONTH_DAYS.each do |(day_label, val)|
                      option(value: val, selected: frequency == "monthly" && settlement_day == val) { plain day_label }
                    end
                  end
                end
              end
            end

            div(class: "px-6 py-4 border-t border-gray-100 flex justify-end") do
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:check, class: ICON_SM)
                plain "Save schedule"
              end
            end
          end
        end
      end
    end

    # ── Controls card ─────────────────────────────────────────────────────────

    def controls_card
      render UI::Card.new do |c|
        c.header("Approval Controls")
        c.body(padding: false) do
          form(action: merchant_settlement_controls_path(@app), method: "post",
               data: { turbo: false, controller: "approver-count" }) do
            input(type: "hidden", name: "_method",            value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            # Preserve schedule settings so "Save controls" doesn't wipe them
            input(type: "hidden", name: "settlement_frequency", value: frequency)
            case frequency
            when "weekly"  then input(type: "hidden", name: "settlement_day_weekly",  value: settlement_day)
            when "monthly" then input(type: "hidden", name: "settlement_day_monthly", value: settlement_day)
            end

            threshold_section
            approvers_section

            div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
              selected = approver_codes.size
              p(class: TYPE_CAPTION,
                data: { approver_count_target: "label", count: selected }) do
                plain selected == 0 ? "No approvers selected" :
                                      "#{selected} #{"approver".pluralize(selected)} selected"
              end
              render UI::Button.new(variant: :primary, type: "submit") do
                render UI::Icon.new(:check, class: ICON_SM)
                plain "Save controls"
              end
            end
          end
        end
      end
    end

    def threshold_section
      div(class: "px-6 py-5 border-b border-gray-100") do
        form_field("Approval threshold") do
          div(class: "relative") do
            span(class: "absolute left-4 top-1/2 -translate-y-1/2 text-[12.5px] font-semibold " \
                         "text-gray-400 pointer-events-none") do
              plain "GHS"
            end
            input(
              type:        "number",
              name:        "approval_threshold",
              value:       threshold,
              min:         "0",
              step:        "1",
              placeholder: "e.g. 50,000",
              class:       "#{INPUT_FIELD} !pl-14"
            )
          end
          p(class: "#{TYPE_CAPTION} mt-2") do
            plain "Batches at or above this amount require manual approval. Clear to auto-approve all."
          end
        end
      end
    end

    def approvers_section
      div(class: "px-6 py-5") do
        form_field("Approvers") do
          p(class: "#{TYPE_CAPTION} mb-4") do
            plain "Ops Managers who can approve settlement dispatch for #{@app.legal_name || "this merchant"}."
          end

          if @staff.empty?
            div(class: "py-5 text-center rounded-xl bg-gray-50") do
              p(class: "text-[13px] font-semibold text-gray-600 mb-1") { plain "No eligible approvers" }
              p(class: TYPE_CAPTION) do
                plain "Only Ops Managers have the settlement approval permission."
              end
            end
          else
            div(class: "flex flex-col divide-y divide-gray-50 rounded-xl border border-gray-100 overflow-hidden") do
              @staff.each { |u| staff_row(u) }
            end
          end
        end
      end
    end

    def staff_row(user)
      checked  = approver_codes.include?(user.user_code)
      initials = [ user.first_name&.first, user.last_name&.first ].compact.join.upcase.presence || "??"

      label(class: "flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50/60 " \
                   "transition-colors group") do
        input(
          type:    "checkbox",
          name:    "approver_user_codes[]",
          value:   user.user_code,
          checked: checked,
          class:   "w-4 h-4 rounded border-gray-300 accent-brand flex-shrink-0"
        )
        render UI::Avatar.new(initials, size: :sm)
        div(class: "flex-1 min-w-0") do
          p(class: "text-[13px] font-semibold text-gray-800 leading-tight truncate") do
            plain user.full_name.presence || user.email
          end
          p(class: "#{TYPE_CAPTION} leading-tight") { plain user.email }
        end
      end
    end

    # ── Shared ────────────────────────────────────────────────────────────────

    def form_field(label_text, &block)
      div do
        p(class: "#{TEXT_LABEL} mb-2") { plain label_text }
        yield
      end
    end
  end
end
