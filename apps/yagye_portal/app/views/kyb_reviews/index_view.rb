# frozen_string_literal: true

module KybReviews
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "pending",   label: "Pending" },
      { key: "in_review", label: "In Review" },
      { key: "approved",  label: "Approved" },
      { key: "rejected",  label: "Rejected" }
    ].freeze

    def initialize(tab: "pending", applications: [], pagy: nil, stats: {}, mtd_volumes: {})
      @tab          = tab
      @applications = applications
      @pagy         = pagy
      @stats        = stats
      @mtd_volumes  = mtd_volumes
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :kyb_reviews,
        title:      "KYB Review",
        breadcrumbs: [ { label: "KYB Review" } ]
      ) do
        render UI::PageHeader.new(title: "KYB Review", subtitle: "Merchant onboarding applications requiring compliance sign-off.")
        stat_band
        tab_bar
        applications_table
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Pending Review", @stats[:pending].to_s,      icon: :clock,        color: AMBER,  tint: TINT_AMBER)
        stat_cell("In Review",      @stats[:in_review].to_s,    icon: :eye,          color: PURPLE, tint: TINT_PURPLE)
        stat_cell("Approved (30d)", @stats[:approved_30d].to_s, icon: :check_circle, color: GREEN,  tint: TINT_GREEN)
        stat_cell("Rejected (30d)", @stats[:rejected_30d].to_s, icon: :alert_circle, color: RED,    tint: TINT_RED)
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
      tab         = @tab
      mtd_volumes = @mtd_volumes

      render UI::Datatable.new(records: @applications, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header do
          p(class: TYPE_TITLE) { plain "#{@tab.humanize} applications" }
          render UI::Button.new(variant: :secondary) do
            render UI::Icon.new(:download, class: ICON_SM)
            plain "Export"
          end
        end

        t.column("Business") do |a|
          div(class: "flex items-center gap-[10px]") do
            render UI::Avatar.new(a.legal_name&.first(2)&.upcase || "??", size: :sm)
            div do
              p(class: TYPE_BODY_MD) { plain a.legal_name || "—" }
              p(class: TYPE_CAPTION) { plain a.merchant_code || a.application_code }
            end
          end
        end

        t.column("Submitted") do |a|
          span(class: TYPE_CAPTION) { plain a.last_applied_at&.strftime("%d %b %Y") || "—" }
        end

        t.column("Reviewer") do |a|
          if a.reviewed_by.present?
            span(class: TYPE_BODY_MD) { plain a.reviewed_by }
          else
            span(class: "text-[11.5px] text-gray-400") { plain "Unassigned" }
          end
        end

        t.column("Volume (MTD)") do |a|
          minor_units = mtd_volumes[a.merchant_code]
          if minor_units.nil? || minor_units == 0
            span(class: TYPE_CAPTION) { plain a.merchant_code.present? ? "GHS 0.00" : "—" }
          else
            span(class: "text-[13px] font-semibold text-gray-800 tabular-nums") do
              plain format_money(minor_units)
            end
          end
        end

        t.column("Status") { |a| render UI::StatusBadge.new(status: a.status) }

        t.actions do |a|
          a(href: kyb_review_path(a), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "Review"
          end
          if tab == "pending"
            form(action: assign_kyb_review_path(a), method: "post",
                 style: "display:contents") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM) do
                render UI::Icon.new(:user, class: ICON_SM)
                plain "Assign to me"
              end
            end
          end
        end
      end
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
