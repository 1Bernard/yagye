# frozen_string_literal: true

module Merchants
  class SettlementControlsView < ApplicationComponent
    include UI::Theme

    WEEKDAYS = [
      [ "Monday",    "1" ], [ "Tuesday", "2" ], [ "Wednesday", "3" ],
      [ "Thursday",  "4" ], [ "Friday",  "5" ]
    ].freeze

    # Capped at 28 because February has only 28 days in non-leap years.
    # Allowing 29/30/31 would silently skip settlement in short months.
    MONTH_DAYS = (1..28).map { |d| [ "#{d.ordinalize} of the month", d.to_s ] }.freeze

    DELAY_OPTIONS = [
      { value: "0", title: "T+0 · Same Day",         desc: "No clearing delay. All cleared payments are included in that day's settlement run.", tag: "Real-time" },
      { value: "1", title: "T+1 · Next Business Day", desc: "Payments cleared before the previous day's 23:59 GMT cutoff are included in today's run.", badge: "Ghana Standard" },
      { value: "2", title: "T+2 · Two Business Days", desc: "Two business days clearing delay for extended transaction verification." },
      { value: "3", title: "T+3 · Three Business Days", desc: "Three business days clearing delay for elevated risk oversight." }
    ].freeze

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
        div(class: "flex flex-col gap-6") do
          hold_banner if on_hold?
          telemetry_ribbon

          render UI::Grid.new(columns: :sidebar_lg) do
            left_column
            right_column
          end
        end
      end
    end

    private

    # ── Left column (Main Settings Form) ──────────────────────────────────────

    def left_column
      form(id: "settlement-controls-form",
           action: merchant_settlement_controls_path(@app), method: "post",
           data: { turbo: false }) do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        div(class: "flex flex-col gap-5") do
          schedule_card
          sweep_criteria_card
          approval_card
          risk_divider
          reserve_card
          hold_card
          form_action_footer
        end
      end
    end

    # ── Right column (Operational Intelligence) ───────────────────────────────

    def right_column
      div(class: "self-start sticky top-6 flex flex-col gap-5") do
        operational_simulator_card
        how_it_works_card
      end
    end

    # ── Telemetry Posture Ribbon (Replaces raw dot string) ────────────────────

    def telemetry_ribbon
      freq_label  = { "daily" => "Daily (Business days)", "weekly" => "Weekly (Consolidated)", "monthly" => "Monthly (Scheduled)" }[frequency] || "Daily"
      delay_label = delay_days == "0" ? "T+0 (Same day)" : "T+#{delay_days} (#{delay_days == '1' ? 'Next business day' : "#{delay_days} business days"})"
      min_label   = "GHS #{minimum_payout_ghs}"
      res_label   = reserve_rate_pct == "0.00" ? "0.00% (No reserve)" : "#{reserve_rate_pct}% (#{reserve_release_days}d hold)"

      div(class: "#{SURFACE_CARD} overflow-hidden") do
        div(class: "grid grid-cols-2 sm:grid-cols-5 gap-[1px] bg-gray-100") do
          telemetry_stat("Frequency",       freq_label)
          telemetry_stat("Clearing Lag",    delay_label)
          telemetry_stat("Min Payout",      min_label,  mono: true)
          telemetry_stat("Rolling Reserve", res_label)

          div(class: "flex items-center justify-center px-5 py-3.5 bg-white") do
            if on_hold?
              render UI::Chip.new(label: "On Hold", colors: STATUS_WARNING)
            else
              render UI::Chip.new(label: "Active", colors: STATUS_SUCCESS)
            end
          end
        end
      end
    end

    def telemetry_stat(label, value, mono: false)
      div(class: "flex flex-col px-5 py-3.5 bg-white") do
        p(class: TYPE_MICRO) { plain label }
        p(class: "#{mono ? TYPE_MONO : TYPE_BODY_MD} mt-0.5") { plain value }
      end
    end

    # ── Hold banner (Top level alert when on hold) ────────────────────────────

    def hold_banner
      div(class: "rounded-2xl border border-amber-200 bg-amber-50/90 px-6 py-4") do
        div(class: "flex items-start gap-4") do
          div(class: "w-9 h-9 rounded-xl bg-amber-100 flex items-center justify-center flex-shrink-0 text-amber-600 mt-0.5") do
            render UI::Icon.new(:alert_triangle, class: "w-5 h-5")
          end
          div(class: "flex-1 min-w-0") do
            p(class: "#{TYPE_TITLE} text-amber-900 leading-tight") do
              plain "This merchant is currently on settlement hold"
            end
            if hold_reason_value.present?
              p(class: "#{TYPE_CAPTION} text-amber-800 mt-1 leading-relaxed") { plain hold_reason_value }
            end
            p(class: "#{TYPE_CAPTION} text-amber-700/80 mt-1.5") do
              plain "Automated settlement payouts are currently paused. Scroll down to the Settlement Hold section to lift this hold."
            end
          end
        end
      end
    end

    # ── Schedule Card ─────────────────────────────────────────────────────────

    def schedule_card
      render UI::Card.new do |c|
        c.header("Payout Schedule", icon: :calendar)
        c.body(padding: false) do
          div(class: "p-6 flex flex-col gap-6", data: { controller: "schedule-picker" }) do
            div do
              p(class: "#{TEXT_LABEL} mb-1") { plain "Release frequency" }
              p(class: "#{TYPE_CAPTION} mb-3.5") do
                plain "Choose how frequently accumulated net settled funds are disbursed to the merchant's verified bank account."
              end

              div(class: "grid grid-cols-1 sm:grid-cols-3 gap-3") do
                frequency_option("daily", "Daily", "Every Ghana business day", badge: "Standard")
                frequency_option("weekly", "Weekly", "Consolidated weekly payout")
                frequency_option("monthly", "Monthly", "Single monthly disbursement")
              end
            end

            div(class: "border-t border-gray-100 pt-5 #{frequency == 'weekly' ? '' : 'hidden'}",
                data: { schedule_picker_target: "weekday" }) do
              form_field("Day of week", hint: "Settlement payout is compiled and dispatched every week on this business day at 06:00 GMT.") do
                div(class: "grid grid-cols-2 sm:grid-cols-5 gap-2.5") do
                  WEEKDAYS.each do |(day_name, val)|
                    weekday_pill(day_name, val)
                  end
                end
              end
            end

            div(class: "border-t border-gray-100 pt-5 #{frequency == 'monthly' ? '' : 'hidden'}",
                data: { schedule_picker_target: "monthday" }) do
              form_field("Day of month", hint: "Capped at the 28th to ensure reliable recurring execution in February and 30-day months.") do
                div(class: "relative") do
                  select(name: "settlement_day_monthly", class: SELECT_FIELD) do
                    MONTH_DAYS.each do |(day_label, val)|
                      option(value: val, selected: frequency == "monthly" && settlement_day == val) { plain day_label }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    def frequency_option(val, title, subtitle, badge: nil)
      selected = (frequency == val)

      label(
        class: "relative flex flex-col p-4 rounded-xl border cursor-pointer transition-all duration-150 " \
               "#{selected ? 'border-[#3D47F5] bg-indigo-50/20 ring-1 ring-[#3D47F5]/20' : 'border-gray-200 bg-white hover:border-gray-300'}",
        data: {
          schedule_picker_target: "card",
          frequency_value: val
        }
      ) do
        input(
          type:    "radio",
          name:    "settlement_frequency",
          value:   val,
          checked: selected,
          class:   "sr-only",
          data:    { action: "change->schedule-picker#toggle" }
        )

        div(class: "flex items-center justify-between mb-2") do
          div(class: "flex items-center gap-2") do
            span(
              class: "w-4 h-4 rounded-full border flex items-center justify-center transition-colors " \
                     "#{selected ? 'border-[#3D47F5] bg-[#3D47F5]' : 'border-gray-300 bg-white'}",
              data: { check_indicator: true }
            ) do
              span(class: "w-1.5 h-1.5 rounded-full bg-white")
            end
            p(class: "#{TYPE_TITLE} leading-tight") { plain title }
          end

          if badge
            span(class: "#{BADGE_XS} bg-indigo-50", style: "color:#{BRAND}") do
              plain badge
            end
          end
        end

        p(class: "#{TYPE_CAPTION} leading-snug pl-6") { plain subtitle }
      end
    end

    def weekday_pill(day_name, val)
      selected = (frequency == "weekly" && settlement_day == val)

      label(
        class: "#{TYPE_BODY_MD} flex items-center justify-center py-2.5 px-3 rounded-lg border cursor-pointer transition-all " \
               "#{selected ? 'border-[#3D47F5] bg-indigo-50/40 font-semibold' : 'border-gray-200 bg-white hover:border-gray-300'}",
        style: selected ? "color:#{BRAND}" : nil,
        data: { schedule_picker_target: "weekdayCard", weekday_value: val }
      ) do
        input(
          type:    "radio",
          name:    "settlement_day_weekly",
          value:   val,
          checked: selected,
          class:   "sr-only",
          data:    { action: "change->schedule-picker#toggle" }
        )
        plain day_name
      end
    end

    # ── Sweep Criteria Card ───────────────────────────────────────────────────

    def sweep_criteria_card
      render UI::Card.new do |c|
        c.header("Settlement Timing", icon: :clock)
        c.body(padding: false) do
          div(class: "p-6 flex flex-col gap-6", data: { controller: "delay-picker" }) do
            div do
              p(class: "#{TEXT_LABEL} mb-1") { plain "Settlement delay" }
              p(class: "#{TYPE_CAPTION} mb-3.5") do
                plain "The number of days Yagye holds cleared funds before including them in a settlement payout."
              end

              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-3") do
                DELAY_OPTIONS.each do |opt|
                  delay_option_card(opt)
                end
              end
            end

            div(class: "border-t border-gray-100 pt-5") do
              form_field("Minimum payout amount (GHS)", hint: "Payouts below this amount are carried over to the next scheduled run to avoid micro-batch fees. Ghana market default is GHS 50.00.") do
                div(class: "relative max-w-sm") do
                  span(class: "absolute left-3.5 top-1/2 -translate-y-1/2 px-2 py-0.5 rounded bg-gray-100 #{TYPE_CAPTION} font-semibold pointer-events-none select-none") do
                    plain "GHS"
                  end
                  input(
                    type:        "number",
                    name:        "minimum_payout_ghs",
                    value:       minimum_payout_ghs,
                    min:         "0",
                    step:        "0.01",
                    placeholder: "50.00",
                    class:       "#{INPUT_FIELD} !pl-16 font-mono text-[13.5px] tabular-nums"
                  )
                end
              end
            end
          end
        end
      end
    end

    def delay_option_card(opt)
      val = opt[:value]
      selected = (delay_days == val)

      label(
        class: "relative flex flex-col p-4 rounded-xl border cursor-pointer transition-all duration-150 " \
               "#{selected ? 'border-[#3D47F5] bg-indigo-50/25 ring-1 ring-[#3D47F5]/25' : 'border-gray-200 bg-white hover:border-gray-300'}",
        data: {
          delay_picker_target: "card",
          delay_value: val
        }
      ) do
        input(
          type:    "radio",
          name:    "settlement_delay_days",
          value:   val,
          checked: selected,
          class:   "sr-only",
          data:    { action: "change->delay-picker#select" }
        )

        div(class: "flex items-center justify-between mb-1.5") do
          div(class: "flex items-center gap-2") do
            span(
              class: "w-4 h-4 rounded-full border flex items-center justify-center transition-colors " \
                     "#{selected ? 'border-[#3D47F5] bg-[#3D47F5]' : 'border-gray-300 bg-white'}",
              data: { radio_indicator: true }
            ) do
              span(class: "w-1.5 h-1.5 rounded-full bg-white")
            end
            p(class: "#{TYPE_TITLE} leading-tight") { plain opt[:title] }
          end

          if opt[:badge]
            span(class: "#{BADGE_XS} #{STATUS_SUCCESS}") { plain opt[:badge] }
          elsif opt[:tag]
            span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") { plain opt[:tag] }
          end
        end

        p(class: "#{TYPE_CAPTION} leading-snug pl-6") { plain opt[:desc] }
      end
    end

    # ── Dual-Control & Approvals Card ─────────────────────────────────────────

    def approval_card
      render UI::Card.new do |c|
        c.header("Dual-Control & Approvals", icon: :shield)
        c.body(padding: false) do
          div(class: "p-6 flex flex-col gap-6", data: { controller: "approver-count" }) do
            form_field("Approval threshold (GHS)", hint: "Settlement payouts at or above this amount are held for review and require dual-control approval by an authorized Ops Manager before dispatch. Leave blank to dispatch all payouts automatically.") do
              div(class: "relative max-w-sm") do
                span(class: "absolute left-3.5 top-1/2 -translate-y-1/2 px-2 py-0.5 rounded bg-gray-100 #{TYPE_CAPTION} font-semibold pointer-events-none select-none") do
                  plain "GHS"
                end
                input(
                  type:        "number",
                  name:        "approval_threshold",
                  value:       threshold,
                  min:         "0",
                  step:        "1",
                  placeholder: "e.g. 50,000 (blank = auto-dispatch)",
                  class:       "#{INPUT_FIELD} !pl-16 font-mono text-[13.5px] tabular-nums"
                )
              end
            end

            div(class: "border-t border-gray-100 pt-5") do
              div(class: "flex items-center justify-between mb-3.5") do
                div do
                  p(class: TEXT_LABEL) { plain "Authorized Approvers" }
                  p(class: "#{TYPE_CAPTION} mt-0.5") do
                    plain "Designated Ops Managers who can authorize settlement dispatch for #{@app.legal_name || "this merchant"}."
                  end
                end
                span(class: "#{BADGE} #{STATUS_NEUTRAL} tabular-nums flex-shrink-0",
                     data: { approver_count_target: "label" }) do
                  selected = approver_codes.size
                  plain selected == 0 ? "No approvers selected" : "#{selected} #{'approver'.pluralize(selected)} authorized"
                end
              end

              if @staff.empty?
                div(class: "py-6 text-center rounded-xl bg-gray-50/70 border border-dashed border-gray-200") do
                  p(class: TYPE_BODY_MD) { plain "No eligible Ops Managers found" }
                  p(class: "#{TYPE_CAPTION} mt-1") { plain "Staff members require the 'settlements.approve_dispatch' permission to authorize batches." }
                end
              else
                div(class: "grid grid-cols-1 sm:grid-cols-2 gap-3") do
                  @staff.each { |u| approver_card(u) }
                end
              end
            end
          end
        end
      end
    end

    def approver_card(user)
      checked  = approver_codes.include?(user.user_code)
      initials = [ user.first_name&.first, user.last_name&.first ].compact.join.upcase.presence || "??"

      label(
        class: "flex items-center gap-3.5 p-3.5 rounded-xl border cursor-pointer transition-all " \
               "#{checked ? 'border-[#3D47F5] bg-indigo-50/20' : 'border-gray-200 bg-white hover:border-gray-300'}",
        data: { approver_card: true }
      ) do
        input(
          type:    "checkbox",
          name:    "approver_user_codes[]",
          value:   user.user_code,
          checked: checked,
          class:   "#{CHECKBOX_INPUT} flex-shrink-0 cursor-pointer"
        )
        render UI::Avatar.new(initials, size: :sm)
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2") do
            p(class: "#{TYPE_BODY_MD} leading-tight truncate") do
              plain user.full_name.presence || user.email
            end
            span(class: "#{BADGE_XS} #{STATUS_NEUTRAL} uppercase tracking-wider flex-shrink-0") do
              plain "Ops Manager"
            end
          end
          p(class: "#{TYPE_CAPTION} truncate mt-0.5") { plain user.email }
        end
      end
    end

    # ── Risk Divider ──────────────────────────────────────────────────────────

    def risk_divider
      div(class: "flex items-center gap-3 px-1 my-1") do
        div(class: "flex-1 h-px bg-gray-100")
        div(class: "flex items-center gap-1.5 text-gray-400") do
          render UI::Icon.new(:shield, class: "w-3.5 h-3.5")
          span(class: TYPE_MICRO) do
            plain "Risk Controls"
          end
        end
        div(class: "flex-1 h-px bg-gray-100")
      end
    end

    # ── Rolling Reserve Card ──────────────────────────────────────────────────

    def reserve_card
      render UI::Card.new do |c|
        c.header("Rolling Reserve", icon: :shield)
        c.body(padding: false) do
          div(class: "p-6 flex flex-col gap-6", data: { controller: "reserve-calculator" }) do
            div do
              p(class: "#{TEXT_LABEL} mb-1") { plain "Reserve Policy" }
              p(class: "#{TYPE_CAPTION} mb-4") do
                plain "A percentage withheld from each payout and held by Yagye until the reserve period expires, covering chargeback exposure, refund liability, and compliance risks."
              end

              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
                div do
                  p(class: "#{TYPE_BODY_MD} mb-1.5") { plain "Reserve rate (%)" }
                  div(class: "relative") do
                    input(
                      type:        "number",
                      name:        "reserve_rate_pct",
                      value:       reserve_rate_pct,
                      min:         "0",
                      max:         "25",
                      step:        "0.01",
                      placeholder: "0.00",
                      class:       "#{INPUT_FIELD} !pr-10 font-mono text-[13.5px] tabular-nums",
                      data:        { action: "input->reserve-calculator#calculate", reserve_calculator_target: "rate" }
                    )
                    span(class: "absolute right-3.5 top-1/2 -translate-y-1/2 #{TYPE_CAPTION} select-none") { plain "%" }
                  end
                  p(class: "#{TYPE_CAPTION} mt-1.5") { plain "Industry standard: 5–10% for newly onboarded merchants; 0% for clean track records." }
                end

                div do
                  p(class: "#{TYPE_BODY_MD} mb-1.5") { plain "Reserve hold period (days)" }
                  div(class: "relative") do
                    input(
                      type:        "number",
                      name:        "reserve_release_days",
                      value:       reserve_release_days,
                      min:         "30",
                      max:         "365",
                      step:        "1",
                      placeholder: "90",
                      class:       "#{INPUT_FIELD} !pr-14 font-mono text-[13.5px] tabular-nums",
                      data:        { action: "input->reserve-calculator#calculate", reserve_calculator_target: "days" }
                    )
                    span(class: "absolute right-3.5 top-1/2 -translate-y-1/2 #{TYPE_CAPTION} select-none") { plain "days" }
                  end
                  p(class: "#{TYPE_CAPTION} mt-1.5") { plain "How long reserved funds are held before automatic release. Ghana market standard: 90 days." }
                end
              end
            end

            # Real-time simulation
            div(class: "rounded-xl border border-gray-100 bg-gray-50 p-4") do
              div(class: "flex items-start gap-3") do
                div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5",
                    style: "background:#{TINT_BRAND}") do
                  span(style: "color:#{BRAND}") { render UI::Icon.new(:shield, class: "w-4 h-4") }
                end
                div(class: "flex-1 min-w-0") do
                  p(class: "#{TYPE_BODY_MD} leading-tight") do
                    plain "Preview · GHS 10,000 Settlement Batch"
                  end
                  p(class: "#{TYPE_CAPTION} mt-0.5", data: { reserve_calculator_target: "previewNotice" }) do
                    plain "100% of cleared funds are disbursed immediately (0.00% reserve held)."
                  end

                  div(class: "grid grid-cols-1 sm:grid-cols-3 gap-3 mt-3 pt-3 border-t border-gray-100") do
                    div do
                      p(class: "#{TYPE_MICRO} mb-0.5") { plain "Amount Disbursed" }
                      p(class: "#{TYPE_TITLE} font-mono tabular-nums",
                        style: "color:#{GREEN}",
                        data: { reserve_calculator_target: "immediateAmount" }) { plain "GHS 10,000.00" }
                    end
                    div do
                      p(class: "#{TYPE_MICRO} mb-0.5") { plain "Reserve Withheld" }
                      p(class: "#{TYPE_TITLE} font-mono tabular-nums",
                        style: "color:#{BRAND}",
                        data: { reserve_calculator_target: "heldAmount" }) { plain "GHS 0.00" }
                    end
                    div do
                      p(class: "#{TYPE_MICRO} mb-0.5") { plain "Automatic Release" }
                      p(class: "#{TYPE_TITLE} font-mono tabular-nums text-gray-700",
                        data: { reserve_calculator_target: "holdPeriod" }) { plain "#{reserve_release_days} days" }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # ── Settlement Hold Card (Emergency Circuit Breaker) ──────────────────────

    def hold_card
      render UI::Card.new do |c|
        c.header("Settlement Hold", icon: :alert_triangle)
        c.body(padding: false) do
          div(data: { controller: "hold-toggle" }) do
            label(class: "flex items-center justify-between gap-4 px-5 py-4 cursor-pointer hover:bg-gray-50/40 transition-colors") do
              div(class: "flex-1 min-w-0") do
                p(class: TYPE_BODY_MD) { plain "Place merchant on settlement hold" }
                p(class: "#{TYPE_CAPTION} mt-0.5 leading-relaxed") do
                  plain "Pauses automated settlement payouts only — payment collection, MoMo processing, and KYB remain fully active."
                end
              end
              input(
                type:    "checkbox",
                name:    "on_hold",
                value:   "1",
                checked: on_hold?,
                class:   "#{CHECKBOX_INPUT} accent-amber-600 flex-shrink-0 cursor-pointer",
                data:    { action: "change->hold-toggle#toggle", hold_toggle_target: "checkbox" }
              )
            end

            div(data: { hold_toggle_target: "reason" },
                style: on_hold? ? "" : "display:none",
                class: "border-t border-gray-50 px-5 pb-5 pt-4") do
              form_field("Reason for hold", hint: "Internal ops justification — not visible to the merchant.") do
                textarea(
                  name:        "hold_reason",
                  rows:        "3",
                  placeholder: "Dispute spike, pending KYB review, fraud investigation...",
                  class:       "#{INPUT_FIELD} resize-none"
                ) { plain hold_reason_value }
              end
            end
          end
        end
      end
    end

    # ── Form-Attached Action Footer ───────────────────────────────────────────

    def form_action_footer
      div(class: "border-t border-gray-100 pt-5 flex flex-col sm:flex-row items-center justify-between gap-4") do
        div(class: "flex items-center gap-2.5") do
          span(class: "w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0",
               style: "background:#{TINT_GRAY}") do
            span(style: "color:#{MUTED_TEXT}") { render UI::Icon.new(:info_circle, class: "w-3.5 h-3.5") }
          end
          p(class: "#{TYPE_CAPTION} leading-snug") do
            plain "Changes take effect from the next settlement run at 06:00 GMT."
          end
        end

        div(class: "flex items-center gap-3 w-full sm:w-auto justify-end") do
          a(href: merchant_settlement_controls_path(@app), class: BTN_GHOST) do
            plain "Discard changes"
          end
          render UI::Button.new(variant: :primary, type: "submit") do
            render UI::Icon.new(:check, class: ICON_SM)
            plain "Save settlement controls"
          end
        end
      end
    end

    # ── Right Column Operational Simulator & Info Cards ───────────────────────

    def operational_simulator_card
      next_run = next_run_time

      render UI::Card.new do |c|
        c.header("Settlement Schedule", icon: :calendar)
        c.body do
          div(class: "flex flex-col gap-4") do
            div(class: "flex items-start gap-3") do
              div(class: "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5",
                  style: "background:#{TINT_BRAND}") do
                span(style: "color:#{BRAND}") { render UI::Icon.new(:clock, class: "w-4 h-4") }
              end
              div do
                p(class: "#{TYPE_MICRO} mb-0.5") { plain "Next settlement run" }
                p(class: "#{TYPE_TITLE}") { plain fmt_next_run(next_run) }
                p(class: "#{TYPE_CAPTION} mt-0.5") { plain next_run_hint }
              end
            end

            div(class: "border-t border-gray-100 pt-3 flex items-start gap-3") do
              div(class: "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5",
                  style: "background:#{TINT_GRAY}") do
                span(style: "color:#{MUTED_TEXT}") { render UI::Icon.new(:info_circle, class: "w-3.5 h-3.5") }
              end
              div do
                p(class: "#{TYPE_BODY_MD} leading-tight") { plain "Eligibility cutoff" }
                p(class: "#{TYPE_CAPTION} mt-0.5") do
                  plain "Payments must clear by 23:59 GMT the day before each scheduled run to qualify."
                end
              end
            end
          end
        end
      end
    end

    def how_it_works_card
      render UI::Card.new do |c|
        c.header("How it works", icon: :info_circle)
        c.body do
          div(class: "flex flex-col gap-5") do
            info_point(
              :calendar,
              "Payout schedule",
              "Daily releases funds every Ghana business day. Weekly or monthly works well for merchants who prefer " \
              "consolidated payouts. Settlement runs are automatically skipped on weekends and public holidays — " \
              "including Easter and National Farmers' Day (first Friday of December)."
            )
            info_point(
              :clock,
              "Settlement timing",
              "The clearing delay controls which payments qualify for each settlement run. At T+1 (Ghana market " \
              "standard), only payments cleared before the previous day's 23:59 GMT cutoff are eligible. The " \
              "minimum payout prevents micro-batches — GHS 50 is the industry default. Payouts below the " \
              "minimum are carried over to the next scheduled run."
            )
            info_point(
              :check_circle,
              "Approval controls",
              "Payouts above the threshold are held for review until an Ops Manager approves dispatch. Use this " \
              "for new or high-volume merchants. Leave the threshold blank to dispatch all payouts automatically."
            )

            div(class: "flex items-center gap-3 my-1") do
              div(class: "flex-1 h-px bg-gray-100")
              span(class: "#{TYPE_MICRO} text-gray-300") { plain "Risk" }
              div(class: "flex-1 h-px bg-gray-100")
            end

            info_point(
              :shield,
              "Rolling reserve",
              "A percentage withheld from each payout and held by Yagye until the reserve hold period expires. " \
              "Common use cases: new merchant onboarding (first 90 days), elevated chargeback rate (>1%), or an " \
              "active compliance flag. Industry range is 5–10% held for 90 days. Set to 0% once the merchant " \
              "has a clean track record."
            )
            info_point(
              :alert_circle,
              "Settlement hold vs. suspension",
              "A hold pauses settlements only — the merchant can still process payments and customers are unaffected. " \
              "Merchant suspension (from the merchant profile) stops all payment processing. Use a hold while " \
              "investigating a dispute spike or a pending KYB update."
            )
          end
        end
      end
    end

    def info_point(icon, title, body)
      div(class: "flex items-start gap-3") do
        div(class: "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 mt-[1px]",
            style: "background:#{TINT_BRAND}") do
          span(class: "flex #{ICON_SM}", style: "color:#{BRAND}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "#{TYPE_BODY_MD} leading-tight") { plain title }
          p(class: "#{TYPE_CAPTION} mt-[3px] leading-relaxed") { plain body }
        end
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

    def delay_days
      @controls["settlement_delay_days"]&.to_s || "0"
    end

    def minimum_payout_ghs
      pesewas = @controls["minimum_payout_pesewas"]
      pesewas ? format("%.2f", pesewas.to_f / 100) : "50.00"
    end

    def reserve_rate_pct
      bps = @controls["reserve_rate_bps"]
      bps ? format("%.2f", bps.to_f / 100) : "0.00"
    end

    def reserve_release_days
      @controls["reserve_release_days"]&.to_s || "90"
    end

    def on_hold?
      @controls["on_hold"] == true || @controls["on_hold"] == "true"
    end

    def hold_reason_value
      @controls["hold_reason"].to_s
    end

    def next_run_time
      now = Time.now.utc
      today_run = Time.utc(now.year, now.month, now.day, 6, 0, 0)
      case frequency
      when "daily"
        candidate = now < today_run ? today_run : today_run + 86_400
        candidate += 86_400 while candidate.wday == 0 || candidate.wday == 6
        candidate
      when "weekly"
        target = settlement_day.to_i.clamp(1, 5)
        diff = (target - now.wday) % 7
        diff = 7 if diff == 0 && now >= today_run
        today_run + diff * 86_400
      when "monthly"
        target_day = settlement_day.to_i.clamp(1, 28)
        candidate = Time.utc(now.year, now.month, target_day, 6, 0, 0)
        if now >= candidate
          next_month = now.month == 12 ? 1 : now.month + 1
          next_year  = now.month == 12 ? now.year + 1 : now.year
          candidate  = Time.utc(next_year, next_month, target_day, 6, 0, 0)
        end
        candidate += 86_400 while candidate.wday == 0 || candidate.wday == 6
        candidate
      else
        today_run
      end
    end

    def fmt_next_run(t)
      now      = Time.now.utc
      today    = Date.new(now.year, now.month, now.day)
      run_date = Date.new(t.year, t.month, t.day)
      if run_date == today
        "Today at 06:00 GMT"
      elsif run_date == today + 1
        "Tomorrow at 06:00 GMT"
      else
        t.strftime("%-d %b at 06:00 GMT")
      end
    end

    def next_run_hint
      case frequency
      when "daily"
        "Runs every Ghana business day at 06:00 GMT."
      when "weekly"
        day_name = Date::DAYNAMES[settlement_day.to_i] || "the configured day"
        "Runs every #{day_name} at 06:00 GMT."
      when "monthly"
        "Runs on the #{settlement_day.to_i.ordinalize} of each month at 06:00 GMT."
      else
        "Runs at 06:00 GMT on the next Ghana business day."
      end
    end

    def form_field(label_text, hint: nil, &block)
      div do
        p(class: "#{TEXT_LABEL} mb-1") { plain label_text }
        if hint
          p(class: "#{TYPE_CAPTION} mb-3") { plain hint }
        end
        yield
      end
    end
  end
end
