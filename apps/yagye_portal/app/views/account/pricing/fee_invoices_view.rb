# frozen_string_literal: true

module Account
  module Pricing
    class FeeInvoicesView < ApplicationComponent
      include UI::Theme

      def initialize(invoices:)
        @invoices = invoices
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :settings_pricing,
          title:       "Fee Invoices",
          breadcrumbs: [
            { label: "Pricing & Fees", href: settings_pricing_path },
            { label: "Fee Invoices" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Platform Fee Invoices",
            subtitle: "Monthly consolidated fee invoices for your account."
          )

          invoices_table
        end
      end

      private

      def invoices_table
        render UI::Datatable.new(
          records:       @invoices,
          pagy:          nil,
          empty_message: "No fee invoices yet. Invoices are generated at the start of each month."
        ) do |t|
          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Invoice ID", class: "font-mono text-[11.5px]") do |inv|
            plain(inv["id"] || "—")
          end

          t.column("Period") do |inv|
            start_s = inv["period_start"] ? Date.parse(inv["period_start"].to_s).strftime("%b %Y") : "—"
            plain start_s
          end

          t.column("Amount", class: "tabular-nums text-right font-semibold") do |inv|
            cur = inv["currency"] || "GHS"
            plain format_money(inv["total_amount"].to_i, currency: cur)
          end

          t.column("Collection") do |inv|
            method = inv["collection_method"] || "—"
            plain method.to_s.humanize
          end

          t.column("Status") do |inv|
            state = inv["state"] || "draft"
            css   = case state
                    when "collected"   then "bg-green-50 text-green-700"
                    when "issued",
                         "collecting" then "bg-blue-50 text-blue-700"
                    when "overdue"     then "bg-red-50 text-red-700"
                    when "written_off" then "bg-gray-100 text-gray-500"
                    else                    "bg-amber-50 text-amber-700"
                    end
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium #{css}") do
              plain state.humanize
            end
          end

          t.column("Due") do |inv|
            due = inv["due_at"]
            plain(due ? Time.parse(due).strftime("%d %b %Y") : "—")
          end

          t.column("Collected") do |inv|
            col = inv["collected_at"]
            plain(col ? Time.parse(col).strftime("%d %b %Y") : "—")
          end
        end
      end
    end
  end
end
