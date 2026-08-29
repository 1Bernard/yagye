# frozen_string_literal: true

module KybReviews
  class IndexPage < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "pending",   label: "Pending" },
      { key: "in_review", label: "In Review" },
      { key: "approved",  label: "Approved" },
      { key: "rejected",  label: "Rejected" }
    ].freeze

    def initialize(tab: "pending", applications: [], pagy: nil)
      @tab          = tab
      @applications = applications
      @pagy         = pagy
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :kyb_reviews,
        title:      "KYB Review",
        breadcrumbs: [ { label: "KYB Review" } ]
      ) do
        page_header
        stat_band
        tab_bar
        applications_table
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:24px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Compliance" }
          h1(style: TYPE_DISPLAY) { "KYB Review Queue" }
        end
        div(style: "display:flex;gap:10px") do
          button(type: "button", class: BTN_SECONDARY) do
            render UI::Icon.new(:download, class: ICON_SM)
            "Export"
          end
        end
      end
    end

    def stat_band
      div(class: "#{STAT_BAND} mb-6") do
        stat_cell("Pending Review", "0", color: "#f59e0b")
        stat_cell("In Review",      "0", color: "#6366f1")
        stat_cell("Approved (30d)", "0", color: "#16a34a")
        stat_cell("Rejected (30d)", "0", color: "#dc2626")
      end
    end

    def stat_cell(label, value, color: INK)
      div(class: STAT_CELL) do
        p(style: TYPE_MICRO) { label }
        p(style: "font-size:28px;font-weight:700;color:#{color};font-variant-numeric:tabular-nums;" \
                  "line-height:1;margin-top:6px") { value }
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href: kyb_reviews_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    def applications_table
      tab = @tab

      render UI::Datatable.new(records: @applications, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header do
          p(style: TYPE_TITLE) { "#{@tab.humanize} applications" }
        end

        t.column("Business") do |a|
          div(style: "display:flex;align-items:center;gap:10px") do
            render UI::Avatar.new(a.legal_name&.first(2)&.upcase || "??", size: :sm)
            div do
              p(style: TYPE_BODY_MD) { a.legal_name }
              p(style: TYPE_CAPTION) { a.merchant_code }
            end
          end
        end
        t.column("Submitted") { |a| a.last_applied_at&.strftime("%d %b %Y") || "—" }
        t.column("Reviewer") do |a|
          if a.reviewed_by.present?
            plain a.reviewed_by
          else
            span(style: "font-size:11.5px;color:#{SUBTLE_TEXT}") { "Unassigned" }
          end
        end
        t.column("Status") { |a| render UI::StatusBadge.new(status: a.status) }

        t.actions do |a|
          a(href: kyb_review_path(a), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            "Review"
          end
          if tab == "pending"
            button(type: "button", class: DROPDOWN_ITEM) do
              render UI::Icon.new(:user, class: ICON_SM)
              "Assign to me"
            end
          end
        end
      end
    end

    def applicant_cell(app)
      div(style: "display:flex;align-items:center;gap:10px") do
        render UI::Avatar.new(app.legal_name&.first(2)&.upcase || "??", size: :sm)
        div do
          p(style: TYPE_BODY_MD) { app.legal_name }
          p(style: TYPE_CAPTION) { app.merchant_code }
        end
      end
    end

    def unassigned_chip
      span(style: "font-size:11.5px;color:#{SUBTLE_TEXT}") { "Unassigned" }
    end

    def empty_message
      case @tab
      when "pending"   then "No applications awaiting review."
      when "in_review" then "No applications currently under review."
      when "approved"  then "No approved applications in this window."
      when "rejected"  then "No rejected applications in this window."
      else "No applications found."
      end
    end
  end
end
