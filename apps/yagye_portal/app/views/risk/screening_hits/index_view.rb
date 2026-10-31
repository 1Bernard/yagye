# frozen_string_literal: true

module Risk
  module ScreeningHits
    class IndexView < ApplicationComponent
      include UI::Theme

      TABS = [
        { key: "all",           label: "All Open" },
        { key: "sanctions",     label: "Sanctions" },
        { key: "pep",           label: "PEP" },
        { key: "adverse_media", label: "Adverse Media" }
      ].freeze

      LIST_TYPE_BADGE = {
        "sanctions"     => STATUS_FAILED,
        "pep"           => STATUS_WARNING,
        "adverse_media" => STATUS_NEUTRAL
      }.freeze

      def initialize(list_type: "all", records: [], has_more: false, next_cursor: nil, can_dispose: false)
        @list_type   = list_type
        @records     = records
        @has_more    = has_more
        @next_cursor = next_cursor
        @can_dispose = can_dispose
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :risk,
          title:      "Screening Hits",
          breadcrumbs: [
            { label: "Risk & Fraud", path: risk_flagged_payments_path },
            { label: "Screening Hits" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Screening Hits",
            subtitle: "Open AML/sanctions screening hits awaiting compliance disposition."
          )

          stat_band
          tab_bar
          hits_table
        end
      end

      private

      def stat_band
        sanctions_count     = @records.count { |r| r["list_type"] == "sanctions" }
        pep_count           = @records.count { |r| r["list_type"] == "pep" }
        adverse_media_count = @records.count { |r| r["list_type"] == "adverse_media" }

        render UI::Grid.new(columns: 4) do
          stat_cell("Sanctions",     sanctions_count.to_s,     icon: :shield_off,    color: RED,    tint: TINT_RED)
          stat_cell("PEP",           pep_count.to_s,           icon: :user_check,    color: AMBER,  tint: TINT_AMBER)
          stat_cell("Adverse Media", adverse_media_count.to_s, icon: :alert_triangle, color: PURPLE, tint: TINT_PURPLE)
          stat_cell("Total Open",    @records.length.to_s,     icon: :list,          color: GREEN,  tint: TINT_GREEN)
        end
      end

      def tab_bar
        render UI::Tabs.new do |t|
          TABS.each do |tab|
            t.tab tab[:label],
                  href:   risk_screening_hits_path(list_type: tab[:key] == "all" ? nil : tab[:key]),
                  active: @list_type == tab[:key]
          end
        end
      end

      def hits_table
        can_dispose = @can_dispose

        render UI::Datatable.new(records: @records, empty_message: "No open screening hits.") do |t|
          t.column("Matched Name") do |r|
            span(class: "text-[13px] font-semibold text-gray-800") { plain r["matched_name"] }
            br
            span(class: TYPE_CAPTION) { plain r["list_source"] }
          end

          t.column("Type") do |r|
            badge_class = LIST_TYPE_BADGE[r["list_type"]] || STATUS_NEUTRAL
            span(class: "#{BADGE} #{badge_class}") { plain r["list_type"]&.upcase || "—" }
          end

          t.column("Subject") do |r|
            span(class: TYPE_CAPTION) { plain r["subject_type"]&.humanize || "—" }
          end

          t.column("Match Score") do |r|
            score = r["match_score"]
            if score
              pct = (score.to_f * 100).round(1)
              span(class: "#{TYPE_MONO} text-[12px]") { plain "#{pct}%" }
            else
              span(class: TYPE_CAPTION) { plain "—" }
            end
          end

          t.column("Raised") do |r|
            span(class: TYPE_CAPTION) { plain fmt_datetime(r["inserted_at"]) }
          end

          t.actions do |r|
            if can_dispose
              button(
                data: {
                  controller: "modal",
                  action:     "click->modal#open",
                  modal_id:   "dispose-hit-#{r["id"]}"
                },
                class: DROPDOWN_ITEM
              ) do
                render UI::Icon.new(:check_circle, class: ICON_SM)
                plain "Dispose"
              end
            end
          end
        end

        render_dispose_modals if can_dispose

        if @has_more && @next_cursor
          div(class: "mt-4 flex justify-center") do
            a(href: risk_screening_hits_path(list_type: @list_type == "all" ? nil : @list_type, after: @next_cursor),
              class: "px-4 py-2 text-[12.5px] font-medium text-brand border border-brand/30 " \
                     "rounded-xl hover:bg-brand/5 transition-colors") do
              plain "Load more"
            end
          end
        end
      end

      def render_dispose_modals
        @records.each do |r|
          div(id: "dispose-hit-#{r["id"]}", class: "hidden") do
            render UI::Modal.new(title: "Dispose Screening Hit") do
              form(
                action: dispose_risk_screening_hit_path(r["id"]),
                method: :post,
                class:  "space-y-4"
              ) do
                input(type: :hidden, name: :merchant_id, value: r["merchant_id"])

                div do
                  label(class: "block text-[12px] font-medium text-gray-700 mb-1") { plain "Status" }
                  select(name: :status, class: "w-full border border-gray-200 rounded-xl px-3 py-2 text-[13px]") do
                    option(value: "false_positive") { plain "False positive" }
                    unless r["list_type"] == "sanctions"
                      option(value: "true_match_cleared") { plain "True match — cleared" }
                    end
                    option(value: "true_match_blocked") { plain "True match — blocked" }
                  end
                end

                div do
                  label(class: "block text-[12px] font-medium text-gray-700 mb-1") { plain "Reason" }
                  textarea(name: :disposition_reason, rows: 3,
                           class: "w-full border border-gray-200 rounded-xl px-3 py-2 text-[13px]",
                           placeholder: "Describe the basis for this disposition…")
                end

                div(class: "flex justify-end gap-2 pt-2") do
                  button(type: :submit, class: "px-4 py-2 bg-brand text-white text-[12.5px] font-medium rounded-xl hover:bg-brand/90") do
                    plain "Confirm Disposition"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
