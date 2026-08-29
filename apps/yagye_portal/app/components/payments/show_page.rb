# frozen_string_literal: true

module Payments
  class ShowPage < ApplicationComponent
    include UI::Theme

    def initialize(payment:, can_refund: false, can_view_pii: false)
      @payment      = payment
      @can_refund   = can_refund
      @can_view_pii = can_view_pii
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payments,
        title:      @payment.reference.presence || @payment.core_payment_id&.first(12) || @payment.id.to_s,
        breadcrumbs: [
          { label: "Payments", url: payments_path },
          { label: @payment.reference.presence || @payment.core_payment_id&.first(12) || @payment.id.to_s }
        ]
      ) do
        div(style: "display:grid;grid-template-columns:1fr 340px;gap:24px;align-items:start") do
          left_column
          right_column
        end
      end
    end

    private

    def left_column
      div(style: "display:flex;flex-direction:column;gap:20px") do
        amount_card
        details_card
        metadata_card
      end
    end

    def right_column
      div(style: "display:flex;flex-direction:column;gap:20px") do
        timeline_card
        actions_card if @can_refund
      end
    end

    # ── Amount / hero card ────────────────────────────────────────────────────

    def amount_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:28px 32px") do
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:20px") do
          div do
            p(style: "#{TYPE_CAPTION};margin-bottom:4px") { "Transaction amount" }
            p(style: "font-size:36px;font-weight:700;color:#{INK};font-variant-numeric:tabular-nums;line-height:1") do
              @payment.formatted_amount
            end
          end
          render UI::StatusBadge.new(status: @payment.status)
        end
        div(style: "display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:#{BORDER};border-radius:12px;overflow:hidden") do
          meta_cell("Reference", @payment.reference.presence || "—", mono: true)
          meta_cell("Provider",  @payment.provider_label)
          meta_cell("Date",      @payment.created_at.strftime("%d %b %Y, %H:%M"))
        end
      end
    end

    # ── Payment details card ──────────────────────────────────────────────────

    def details_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Payment details" }
        end
        div(style: "padding:0") do
          detail_row("Customer",         customer_value)
          detail_row("Core payment ID",  @payment.core_payment_id || "—", mono: true)
          detail_row("Payment method",   @payment.provider_label)
          detail_row("Status",           nil) { render UI::StatusBadge.new(status: @payment.status) }
          detail_row("Created",          @payment.created_at.strftime("%d %b %Y at %H:%M UTC"))
          detail_row("Settled",          settled_label)
          detail_row("Merchant",         @payment.merchant_code || "—", mono: true)
        end
      end
    end

    # ── Metadata card ─────────────────────────────────────────────────────────

    def metadata_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Metadata" }
        end
        div(style: "padding:16px 24px") do
          pre(style: "#{TYPE_MONO};background:#{SURFACE};border-radius:10px;padding:14px;overflow-x:auto;" \
                     "font-size:11.5px;line-height:1.6;white-space:pre-wrap;word-break:break-all") do
            JSON.pretty_generate(@payment.metadata.presence || {})
          end
        end
      end
    end

    # ── Timeline card ─────────────────────────────────────────────────────────

    def timeline_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Activity timeline" }
        end
        div(style: "padding:20px 24px") do
          timeline_events.each_with_index do |(label, at, color), i|
            timeline_item(label, at, color, last: i == timeline_events.length - 1)
          end
        end
      end
    end

    # ── Actions card ──────────────────────────────────────────────────────────

    def actions_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "padding:20px 24px;border-bottom:1px solid #{BORDER}") do
          p(style: TYPE_TITLE) { "Actions" }
        end
        div(style: "padding:16px 24px;display:flex;flex-direction:column;gap:8px") do
          if @can_refund && @payment.status == "paid"
            button(type: "button", class: BTN_DANGER,
                   style: "width:100%;justify-content:center") do
              render UI::Icon.new(:refresh, class: ICON_SM)
              "Issue refund"
            end
          end
          p(style: "#{TYPE_CAPTION};text-align:center;margin-top:4px") do
            "Refunds are processed within 5–10 business days."
          end
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def detail_row(label, value, mono: false)
      div(style: "display:flex;align-items:center;justify-content:space-between;padding:14px 24px;" \
                 "border-bottom:1px solid #{BORDER}") do
        span(style: TYPE_CAPTION) { label }
        if block_given?
          yield
        else
          span(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value }
        end
      end
    end

    def meta_cell(label, value, mono: false)
      div(style: "background:#fff;padding:14px 18px") do
        p(style: "#{TYPE_MICRO};margin-bottom:3px") { label }
        p(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value }
      end
    end

    def timeline_item(label, timestamp, color, last: false)
      div(style: "display:flex;gap:14px") do
        div(style: "display:flex;flex-direction:column;align-items:center;flex-shrink:0") do
          div(style: "width:10px;height:10px;border-radius:50%;background:#{color};flex-shrink:0;margin-top:3px")
          div(style: "width:1px;flex:1;background:#{BORDER};margin-top:4px") unless last
        end
        div(style: "padding-bottom:#{last ? '0' : '16px'}") do
          p(style: TYPE_BODY_MD) { label }
          p(style: TYPE_CAPTION) { timestamp&.strftime("%d %b %Y, %H:%M") || "—" }
        end
      end
    end

    def timeline_events
      events = [ [ "Payment initiated", @payment.created_at, "#6366f1" ] ]
      events << [ "Processing",         @payment.updated_at, "#f59e0b" ] if @payment.status.in?(%w[processing paid failed])
      events << [ "Payment settled",    @payment.paid_at,    "#16a34a" ] if @payment.paid_at.present?
      events << [ "Payment failed",     @payment.updated_at, "#dc2626" ] if @payment.status == "failed"
      events << [ "Refunded",           @payment.updated_at, "#f59e0b" ] if @payment.status == "refunded"
      events
    end

    def customer_value
      @can_view_pii ? (@payment.customer_msisdn || "—") : @payment.masked_msisdn
    end

    def settled_label
      @payment.paid_at ? @payment.paid_at.strftime("%d %b %Y, %H:%M") : "—"
    end
  end
end
