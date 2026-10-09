# frozen_string_literal: true

module Payments
  module Payouts
    class StatementView < ApplicationComponent
      def initialize(payout:)
        @payout = payout
      end

      def view_template
        doctype
        html(lang: "en") do
          head do
            meta(charset: "UTF-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1")
            title { plain "Payout Statement — #{@payout.payout_code}" }
            style do
              raw safe(<<~CSS)
                *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                       font-size: 13px; color: #111827; background: #fff; padding: 40px; }
                .header { display: flex; justify-content: space-between; align-items: flex-start;
                          padding-bottom: 24px; border-bottom: 2px solid #111827; margin-bottom: 28px; }
                .brand { font-size: 20px; font-weight: 800; letter-spacing: -0.5px; color: #3D47F5; }
                .doc-title { font-size: 11px; font-weight: 600; color: #6b7280; text-transform: uppercase;
                             letter-spacing: 0.06em; margin-top: 2px; }
                .meta { text-align: right; font-size: 11.5px; color: #6b7280; line-height: 1.6; }
                .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1px;
                             background: #e5e7eb; border-radius: 12px; overflow: hidden; margin-bottom: 28px; }
                .stat-cell { background: #f9fafb; padding: 14px 16px; }
                .stat-label { font-size: 10.5px; font-weight: 600; color: #9ca3af;
                              text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
                .stat-value { font-size: 13.5px; font-weight: 600; color: #111827; font-variant-numeric: tabular-nums; }
                table { width: 100%; border-collapse: collapse; margin-bottom: 28px; }
                th { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em;
                     color: #6b7280; padding: 8px 12px; border-bottom: 1px solid #e5e7eb; text-align: left; }
                td { font-size: 12.5px; color: #374151; padding: 10px 12px; border-bottom: 1px solid #f3f4f6; }
                .mono { font-family: "SF Mono", "Fira Code", ui-monospace, monospace; font-size: 12px; }
                .footer { border-top: 1px solid #e5e7eb; padding-top: 16px; font-size: 11px;
                          color: #9ca3af; display: flex; justify-content: space-between; align-items: center; }
                @media print {
                  body { padding: 24px; }
                  @page { margin: 1.5cm; }
                }
              CSS
            end
            script { raw "window.addEventListener('load', () => window.print());" }
          end
          body do
            div(class: "header") do
              div do
                p(class: "brand") { plain "Yagye" }
                p(class: "doc-title") { plain "Payout Statement" }
              end
              div(class: "meta") do
                plain "Generated #{Time.current.strftime("%d %b %Y at %H:%M UTC")}"
                br
                plain "Payout code: #{@payout.payout_code}"
              end
            end

            div(class: "stat-grid") do
              stat_cell("Amount",       @payout.formatted_amount)
              stat_cell("Status",       @payout.state.humanize)
              stat_cell("Destination",  @payout.destination_type&.humanize || "—")
              stat_cell("Scheduled",    @payout.scheduled_for&.strftime("%d %b %Y") || "—")
              stat_cell("Merchant",     @payout.merchant_code || "—")
              stat_cell("Currency",     @payout.currency)
            end

            table do
              thead do
                tr do
                  th { plain "Field" }
                  th { plain "Value" }
                end
              end
              tbody do
                detail_row("Payout code",        @payout.payout_code,                    mono: true)
                detail_row("Merchant code",       @payout.merchant_code || "—",           mono: true)
                detail_row("Amount",              @payout.formatted_amount)
                detail_row("Currency",            @payout.currency)
                detail_row("Status",              @payout.state.humanize)
                detail_row("Mode",                @payout.mode&.capitalize || "—")
                detail_row("Destination type",    @payout.destination_type&.humanize || "—")
                detail_row("Destination",         @payout.destination_fingerprint || "—", mono: true)
                detail_row("Scheduled for",       @payout.scheduled_for&.strftime("%d %b %Y, %H:%M UTC") || "—")
                detail_row("Last updated",        @payout.last_applied_at&.strftime("%d %b %Y, %H:%M UTC") || "—")
                detail_row("Failure code",        @payout.failure_code || "—",            mono: true) if @payout.failure_code.present?
              end
            end

            div(class: "footer") do
              span { plain "Yagye Payments · yagye.com" }
              span { plain "Confidential — for authorized recipients only" }
            end
          end
        end
      end

      private

      def stat_cell(label, value)
        div(class: "stat-cell") do
          p(class: "stat-label") { plain label }
          p(class: "stat-value") { plain value.to_s }
        end
      end

      def detail_row(label, value, mono: false)
        tr do
          td { plain label }
          td(class: mono ? "mono" : "") { plain value.to_s }
        end
      end
    end
  end
end
