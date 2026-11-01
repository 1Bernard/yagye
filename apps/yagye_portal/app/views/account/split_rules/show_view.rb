# frozen_string_literal: true

module Account
  module SplitRules
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(rule:)
        @rule = rule
        @legs = Array(rule["legs"])
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :split_rules,
          title:       @rule["name"].to_s,
          breadcrumbs: [
            { label: "Settings",    href: settings_path },
            { label: "Split Rules", href: split_rules_path },
            { label: @rule["name"].to_s }
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
          hero_card
          legs_card
          records_card
        end
      end

      def hero_card
        div(class: "#{SURFACE_CARD} px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Split rule" }
              p(class: "text-[22px] font-bold text-gray-900 tracking-tight") { plain @rule["name"].to_s }
            end
            div(class: "flex flex-col items-end gap-2") do
              active_badge_el(@rule["active"])
              mode_badge_el(@rule["mode"])
            end
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Rule ID",  @rule["public_id"].to_s, mono: true)
            meta_cell("Legs",     @legs.size.to_s)
            meta_cell("Created",  fmt_date(parse_ts(@rule["inserted_at"])))
          end
        end
      end

      def legs_card
        render UI::Card.new do |c|
          c.header("Distribution legs", icon: :share)
          c.body(padding: false) do
            if @legs.empty?
              div(class: "px-6 py-8 text-center") do
                p(class: TYPE_CAPTION) { plain "No legs configured." }
              end
            else
              @legs.each_with_index do |leg, i|
                leg_row(leg, i)
              end
            end
          end
        end
      end

      def leg_row(leg, index)
        div(class: "flex items-center justify-between px-6 py-4 #{index > 0 ? 'border-t border-gray-100' : ''}") do
          div(class: "flex flex-col gap-[3px]") do
            p(class: "text-[13px] font-medium text-gray-900 font-mono") do
              plain leg["recipient_merchant_code"].to_s
            end
            p(class: TYPE_CAPTION) { plain "Leg #{index + 1}" }
          end
          div(class: "flex items-center gap-3") do
            split_type_badge(leg["split_type"])
            p(class: "text-[13px] font-semibold text-gray-900") do
              if leg["split_type"] == "percentage"
                plain "#{(leg["value"].to_f / 100).round(2)}%"
              else
                plain format_money(leg["value"].to_i, currency: @rule["currency"] || "GHS")
              end
            end
          end
        end
      end

      def records_card
        records = Array(@rule["recent_records"])
        return if records.empty?

        render UI::Card.new do |c|
          c.header("Recent distributions", icon: :clock)
          c.body(padding: false) do
            records.first(10).each_with_index do |rec, i|
              div(class: "flex items-center justify-between px-6 py-3 #{i > 0 ? 'border-t border-gray-100' : ''}") do
                div do
                  p(class: "font-mono text-[11.5px] text-gray-700") { plain rec["public_id"].to_s }
                  p(class: TYPE_CAPTION) { plain fmt_date(parse_ts(rec["inserted_at"])) }
                end
                div(class: "flex items-center gap-2") do
                  record_state_badge(rec["state"])
                  p(class: "text-[13px] font-medium text-gray-900") { plain format_money(rec["amount"].to_i, currency: rec["currency"] || "GHS") }
                end
              end
            end
          end
        end
      end

      def right_column
        div(class: "flex flex-col gap-4") do
          info_card
          actions_card if @rule["active"]
        end
      end

      def info_card
        render UI::Card.new do |c|
          c.header("Details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Status")  { active_badge_el(@rule["active"]) }
              list.row("Mode")    { mode_badge_el(@rule["mode"]) }
              list.row("Created", fmt_date(parse_ts(@rule["inserted_at"])))
              list.row("Rule ID", mono_text(@rule["public_id"].to_s))
            end
          end
        end
      end

      def actions_card
        render UI::Card.new do |c|
          c.header("Actions")
          c.body do
            form(action: deactivate_split_rule_path(@rule["public_id"]), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit",
                     class: "#{BTN_DANGER} w-full justify-center",
                     data: { confirm: "Deactivate this split rule? In-flight payments will not be affected." }) do
                plain "Deactivate rule"
              end
            end
          end
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────────

      def parse_ts(str)
        str.present? ? Time.parse(str.to_s) : nil
      rescue ArgumentError
        nil
      end

      def active_badge_el(active)
        if active
          span(class: "#{STATUS_SUCCESS} #{BADGE}") { plain "Active" }
        else
          span(class: "#{STATUS_NEUTRAL} #{BADGE}") { plain "Inactive" }
        end
      end

      def mode_badge_el(mode)
        cls = case mode.to_s
              when "live"       then STATUS_SUCCESS
              when "sandbox"    then STATUS_INFO
              when "simulation" then STATUS_NEUTRAL
              else STATUS_NEUTRAL
              end
        span(class: "#{cls} #{BADGE}") { plain mode.to_s.capitalize }
      end

      def split_type_badge(type)
        cls = type == "percentage" ? STATUS_INFO : STATUS_NEUTRAL
        span(class: "#{cls} #{BADGE}") { plain type.to_s.capitalize }
      end

      def record_state_badge(state)
        cls = case state.to_s
              when "settled" then STATUS_SUCCESS
              when "failed"  then STATUS_FAILED
              else STATUS_PENDING
              end
        span(class: "#{cls} #{BADGE}") { plain state.to_s.capitalize }
      end

      def mono_text(val)
        span(class: "font-mono text-[11.5px]") { plain val }
      end
    end
  end
end
