# frozen_string_literal: true

module Account
  module SplitRules
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(rules: [])
        @rules = rules
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :split_rules,
          title:       "Split Rules",
          breadcrumbs: [ { label: "Settings", href: settings_path }, { label: "Split Rules" } ]
        ) do
          header_row
          rules_table
        end
      end

      private

      def header_row
        div(class: "flex items-center justify-between mb-6") do
          div do
            p(class: TYPE_BODY_MD) { plain "Configure how payment revenue is automatically distributed across recipient accounts." }
          end
          a(href: new_split_rule_path, class: BTN_PRIMARY) { plain "New split rule" }
        end
      end

      def rules_table
        render UI::Datatable.new(records: @rules, empty_message: "No split rules configured yet.") do |t|
          t.column("Name")  { |r| plain r["name"].to_s }
          t.column("Legs")  { |r| plain "#{Array(r["legs"]).size} leg#{'s' if Array(r["legs"]).size != 1}" }
          t.column("Mode")  { |r| mode_badge(r["mode"]) }
          t.column("State") { |r| active_badge(r["active"]) }
          t.column("Created") { |r| plain fmt_date(r["inserted_at"] ? Time.parse(r["inserted_at"].to_s) : nil) }

          t.actions do |r|
            a(href: split_rule_path(r["public_id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def mode_badge(mode)
        cls = case mode.to_s
              when "live"       then STATUS_SUCCESS
              when "sandbox"    then STATUS_INFO
              when "simulation" then STATUS_NEUTRAL
              else STATUS_NEUTRAL
              end
        span(class: "#{cls} #{BADGE}") { plain mode.to_s.capitalize }
      end

      def active_badge(active)
        if active
          span(class: "#{STATUS_SUCCESS} #{BADGE}") { plain "Active" }
        else
          span(class: "#{STATUS_NEUTRAL} #{BADGE}") { plain "Inactive" }
        end
      end
    end
  end
end
