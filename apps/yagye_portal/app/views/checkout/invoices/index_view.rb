# frozen_string_literal: true

module Checkout
  module Invoices
    class IndexView < ApplicationComponent
      include UI::Theme

      TABS = [
        { key: "all",     label: "All"     },
        { key: "draft",   label: "Draft"   },
        { key: "open",    label: "Open"    },
        { key: "overdue", label: "Overdue" },
        { key: "paid",    label: "Paid"    },
        { key: "void",    label: "Void"    }
      ].freeze

      def initialize(invoices:, query: nil, tab: "all")
        @invoices = invoices
        @query    = query
        @tab      = tab
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :invoices,
          title:      "Invoices",
          breadcrumbs: [ { label: "Invoices" } ]
        ) do
          render UI::PageHeader.new(title: "Invoices",
                                    subtitle: "Create and manage invoices for your customers.") do
            a(href: new_invoice_path, class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: "w-3 h-3")
              plain "New invoice"
            end
          end
          stat_band
          tab_bar
          invoice_table
        end
      end

      private

      def tab_bar
        render UI::Tabs.new do |t|
          TABS.each do |tab|
            t.tab tab[:label],
                  href:   invoices_path(tab: tab[:key]),
                  active: @tab == tab[:key]
          end
        end
      end

    def stat_band
        open_amt = @invoices.select { |i| i["state"] == "open" }.sum { |i| i["amount_due"].to_i }
        paid_amt = @invoices.select { |i| i["state"] == "paid" }.sum { |i| i["total_amount"].to_i }
        overdue  = @invoices.count  { |i| i["state"] == "overdue" }
        draft_ct = @invoices.count  { |i| i["state"] == "draft" }

        render UI::Grid.new(columns: 4) do
          stat_cell("Outstanding", format_money(open_amt), icon: :clock,        color: TEAL,  tint: TINT_TEAL)
          stat_cell("Collected",   format_money(paid_amt), icon: :check_circle, color: GREEN, tint: TINT_GREEN)
          stat_cell("Overdue",     overdue.to_s,           icon: :alert_circle, color: RED,   tint: TINT_RED)
          stat_cell("Drafts",      draft_ct.to_s,          icon: :file,         color: BRAND, tint: TINT_BRAND)
        end
      end

      def invoice_table
        render UI::Datatable.new(records: @invoices,
                                 empty_message: empty_message) do |t|
          t.header { toolbar_content }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
            plain((i + 1).to_s)
          end

          t.column("Number") do |inv|
            a(href: invoice_path(inv["id"]), class: "#{TYPE_MONO} hover:text-brand no-underline") do
              plain inv["number"] || inv["id"]
            end
          end

          t.column("Customer") do |inv|
            span(class: TYPE_BODY_MD) { plain inv["customer_reference"].presence || "—" }
          end

          t.column("Amount due", class: "text-right tabular-nums") do |inv|
            cls = inv["state"] == "overdue" ? "text-red-600 font-semibold" : "text-gray-800 font-semibold"
            span(class: "text-[13px] #{cls}") { plain format_money(inv["amount_due"].to_i) }
          end

          t.column("Status") do |inv|
            render UI::StatusBadge.new(status: inv["state"])
          end

          t.column("Due date") do |inv|
            due = inv["due_date"]
            if due
              date    = Date.parse(due) rescue nil
              overdue = date && inv["state"] != "paid" && date < Date.today
              cls     = overdue ? "text-red-600 font-semibold" : TYPE_CAPTION
              span(class: cls) { plain date&.strftime("%d %b %Y") || due }
            else
              span(class: TYPE_CAPTION) { plain "—" }
            end
          end

          t.column("Issued") do |inv|
            span(class: TYPE_CAPTION) { plain inv["issue_date"] || "—" }
          end

          t.actions do |inv|
            a(href: invoice_path(inv["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
            if inv["state"] == "draft"
              a(href: edit_invoice_path(inv["id"]), class: DROPDOWN_ITEM) do
                render UI::Icon.new(:edit, class: ICON_SM)
                plain "Edit"
              end
              form(action: issue_invoice_path(inv["id"]), method: "post", style: "display:contents") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:paper_plane, class: ICON_SM)
                  plain "Issue"
                end
              end
            end
            if %w[open partially_paid overdue].include?(inv["state"])
              form(action: void_invoice_path(inv["id"]), method: "post", style: "display:contents") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: "#{DROPDOWN_ITEM} text-red-600",
                       data: { confirm: "Void this invoice? This cannot be undone." }) do
                  render UI::Icon.new(:x, class: ICON_SM)
                  plain "Void"
                end
              end
            end
          end
        end
      end

      def toolbar_content
        form(action: invoices_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          input(type: "hidden", name: "tab", value: @tab)
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search by number or customer…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def format_money(amount_minor, currency = "GHS")
        "#{currency} #{"%.2f" % (amount_minor / 100.0)}"
      end

      def empty_message
        (@tab != "all") || @query.present? ? "No invoices match those filters." : "No invoices yet. Create your first invoice to get started."
      end
    end
  end
end
