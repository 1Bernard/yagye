# frozen_string_literal: true

module Merchants
  class SettlementControlsView < ApplicationComponent
    include UI::Theme

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
        div(class: "max-w-2xl flex flex-col gap-5") do
          info_banner
          schedule_card
          controls_card
        end
      end
    end

    private

    WEEKDAYS = [
      ["Monday",    "1"], ["Tuesday", "2"], ["Wednesday", "3"],
      ["Thursday",  "4"], ["Friday",  "5"]
    ].freeze

    MONTH_DAYS = (1..28).map { |d| ["#{d.ordinalize} of the month", d.to_s] }.freeze

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

    def info_banner
      div(class: "rounded-2xl px-6 py-5 flex items-start gap-4",
          style: "background:rgba(61,71,245,0.06);border:1px solid rgba(61,71,245,0.18)") do
        span(class: "flex-shrink-0 mt-[2px]") do
          render UI::Icon.new(:info_circle, class: "w-5 h-5", style: "color:#3D47F5")
        end
        div do
          p(class: "text-[13.5px] font-semibold text-gray-800 mb-1") do
            plain "How settlement controls work"
          end
          p(class: "#{TYPE_CAPTION} leading-relaxed") do
            plain "When a settlement batch exceeds the approval threshold, it must be manually approved by one of the listed approvers before dispatch. Leave the threshold blank to auto-approve all batches."
          end
        end
      end
    end

    def controls_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Settlement Controls" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Configure approval rules for #{@app.legal_name || @app.merchant_code}."
          end
        end

        form(action: merchant_settlement_controls_path(@app), method: "post",
             data: { turbo: false }) do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          threshold_section
          approvers_section
          save_footer
        end
      end
    end

    def schedule_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Payout Schedule" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "When settled funds are released to #{@app.legal_name || @app.merchant_code}'s bank account."
          end
        end

        form(action: merchant_settlement_controls_path(@app), method: "post",
             data: { turbo: false, controller: "schedule-picker" }) do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "px-6 py-5 border-b border-gray-100") do
            div(class: "flex flex-col gap-4 max-w-sm") do
              # Frequency
              div do
                label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-2") do
                  plain "Release frequency"
                end
                select(
                  name:  "settlement_frequency",
                  class: "w-full h-9 border border-gray-200 rounded-xl px-3 text-[13px] font-medium text-gray-800 bg-white outline-none cursor-pointer",
                  data:  { action: "change->schedule-picker#toggle", schedule_picker_target: "frequency" }
                ) do
                  option(value: "daily",   selected: frequency == "daily")   { plain "Daily — every business day" }
                  option(value: "weekly",  selected: frequency == "weekly")  { plain "Weekly — pick a day" }
                  option(value: "monthly", selected: frequency == "monthly") { plain "Monthly — pick a date" }
                end
              end

              # Weekly day picker
              div(data: { schedule_picker_target: "weekday" },
                  style: frequency == "weekly" ? "" : "display:none") do
                label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-2") do
                  plain "Day of week"
                end
                select(
                  name:  "settlement_day_weekly",
                  class: "w-full h-9 border border-gray-200 rounded-xl px-3 text-[13px] font-medium text-gray-800 bg-white outline-none cursor-pointer"
                ) do
                  WEEKDAYS.each do |(day_name, val)|
                    option(value: val, selected: frequency == "weekly" && settlement_day == val) { plain day_name }
                  end
                end
              end

              # Monthly day picker
              div(data: { schedule_picker_target: "monthday" },
                  style: frequency == "monthly" ? "" : "display:none") do
                label(class: "block text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-2") do
                  plain "Day of month"
                end
                select(
                  name:  "settlement_day_monthly",
                  class: "w-full h-9 border border-gray-200 rounded-xl px-3 text-[13px] font-medium text-gray-800 bg-white outline-none cursor-pointer"
                ) do
                  MONTH_DAYS.each do |(day_label, val)|
                    option(value: val, selected: frequency == "monthly" && settlement_day == val) { plain day_label }
                  end
                end
              end
            end
          end

          div(class: "px-6 py-4 flex justify-end") do
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Save schedule"
            end
          end
        end
      end
    end

    def threshold_section
      div(class: "px-6 py-5 border-b border-gray-100") do
        p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-3") do
          plain "Approval threshold (GHS)"
        end
        div(class: "relative max-w-xs") do
          span(class: "absolute left-3 top-1/2 -translate-y-1/2 text-[13px] font-medium text-gray-400") do
            plain "GHS"
          end
          input(
            type:        "number",
            name:        "approval_threshold",
            value:       threshold,
            min:         "0",
            step:        "1",
            placeholder: "e.g. 50000",
            class:       "w-full pl-12 pr-4 py-2.5 rounded-xl border border-gray-200 text-[13.5px] " \
                         "focus:outline-none focus:ring-2 focus:ring-brand/30 focus:border-brand/60"
          )
        end
        p(class: "#{TYPE_CAPTION} mt-2") do
          plain "Batches at or above this amount require manual approval. Clear to auto-approve all."
        end
      end
    end

    def approvers_section
      div(class: "px-6 py-5 border-b border-gray-100") do
        p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-1") do
          plain "Approvers"
        end
        p(class: "#{TYPE_CAPTION} mb-4") do
          plain "Select Yagye team members who can approve settlement dispatch for this merchant."
        end

        if @staff.empty?
          div(class: "py-6 text-center") do
            p(class: "text-[13px] font-semibold text-gray-600 mb-1") { plain "No eligible approvers" }
            p(class: TYPE_CAPTION) do
              plain "Only Ops Managers have the settlement approval permission. " \
                    "Invite a team member and assign them the Ops Manager role to add them here."
            end
          end
        else
          div(class: "flex flex-col divide-y divide-gray-50") do
            @staff.each { |u| staff_row(u) }
          end
        end
      end
    end

    def staff_row(user)
      checked  = approver_codes.include?(user.user_code)
      initials = [ user.first_name&.first, user.last_name&.first ].compact.join.upcase.presence || "??"

      label(class: "flex items-center gap-4 py-3 cursor-pointer group") do
        input(
          type:    "checkbox",
          name:    "approver_user_codes[]",
          value:   user.user_code,
          checked: checked,
          class:   "w-4 h-4 rounded border-gray-300 accent-brand flex-shrink-0"
        )
        div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 " \
                   "bg-gray-100 border border-gray-200") do
          span(class: "text-[10px] font-bold text-gray-600") { plain initials }
        end
        div(class: "flex-1 min-w-0") do
          p(class: "text-[13px] font-semibold text-gray-800 leading-tight") do
            plain user.full_name.presence || user.email
          end
          p(class: "text-[11.5px] text-gray-400 leading-tight") { plain user.email }
        end
        span(class: "font-mono text-[11px] text-gray-400 flex-shrink-0") { plain user.user_code }
      end
    end

    def save_footer
      div(class: "px-6 py-4 flex items-center justify-between") do
        selected = approver_codes.size
        p(class: TYPE_CAPTION) do
          plain selected == 0 ? "No approvers selected" : "#{selected} approver#{"s" if selected != 1} selected"
        end
        render UI::Button.new(variant: :primary, type: "submit") do
          render UI::Icon.new(:check, class: ICON_SM)
          plain "Save controls"
        end
      end
    end
  end
end
