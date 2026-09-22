# frozen_string_literal: true

module Payments
  class ShowView < ApplicationComponent
    include UI::Theme

    def initialize(payment:, events: [], can_refund: false, can_view_pii: false)
      @payment      = payment
      @events       = events
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
        render UI::Grid.new(columns: :sidebar_lg) do
          left_column
          right_column
        end
      end
    end

    private

    def left_column
      div(class: "flex flex-col gap-5") do
        amount_card
        details_card
        metadata_card
        core_events_card if @events.any?
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        timeline_card
        actions_card if @can_refund
      end
    end

    # ── Amount / hero card ────────────────────────────────────────────────────

    def amount_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
        div(class: "flex items-start justify-between mb-5") do
          div do
            p(class: "#{TYPE_CAPTION} mb-1") { plain "Transaction amount" }
            p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @payment.formatted_amount }
          end
          render UI::StatusBadge.new(@payment.status)
        end
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          meta_cell("Reference", @payment.reference.presence || "—", mono: true)
          meta_cell("Provider") { network_logo_label(@payment) }
          meta_cell("Date",      @payment.created_at.strftime("%d %b %Y, %H:%M"))
        end
      end
    end

    # ── Payment details card ──────────────────────────────────────────────────

    def details_card
      render UI::Card.new do |c|
        c.header("Payment details")
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Customer",        customer_value)
            list.row("Core payment ID", @payment.core_payment_id || "—", mono: true)
            list.row("Payment method") { network_logo_label(@payment) }
            list.row("Status")         { render UI::StatusBadge.new(@payment.status) }
            list.row("Created",        @payment.created_at.strftime("%d %b %Y at %H:%M UTC"))
            list.row("Settled",        settled_label)
            list.row("Merchant",       @payment.merchant_code || "—", mono: true)
            if @payment.fulfilment_type.present?
              list.row("Fulfilment") do
                span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium bg-gray-100 text-gray-600") do
                  plain @payment.fulfilment_type.capitalize
                end
              end
            end
            list.row("Ship to", @payment.shipping_country) if @payment.shipping_country.present?
            unless @payment.billing_shipping_match.nil?
              list.row("Billing = shipping") do
                if @payment.billing_shipping_match
                  span(class: "text-[12px] text-green-700 font-medium") { plain "Match ✓" }
                else
                  span(class: "text-[12px] text-amber-600 font-medium") { plain "Mismatch ✗" }
                end
              end
            end
          end
        end
      end
    end

    # ── Metadata card ─────────────────────────────────────────────────────────

    def metadata_card
      render UI::Card.new do |c|
        c.header("Metadata")
        c.body do
          pre(class: "#{TYPE_MONO} text-[11.5px] bg-gray-50 rounded-xl p-[14px] overflow-x-auto leading-relaxed whitespace-pre-wrap break-all") do
            plain JSON.pretty_generate(@payment.metadata.presence || {})
          end
        end
      end
    end

    # ── Timeline card ─────────────────────────────────────────────────────────

    def timeline_card
      render UI::Card.new do |c|
        c.header("Activity timeline")
        c.body do
          div(class: "flex flex-col") do
            timeline_events.each_with_index do |(label, at, color), i|
              timeline_item(label, at, color, last: i == timeline_events.length - 1)
            end
          end
        end
      end
    end

    # ── Actions card ──────────────────────────────────────────────────────────

    def actions_card
      render UI::Card.new do |c|
        c.header("Actions")
        c.body do
          div(class: "flex flex-col gap-2") do
            if @can_refund && @payment.status == "paid"
              render UI::Button.new(variant: :danger,
                     data: { action: "click->dialog#open", dialog_target_param: "refund-dialog-#{@payment.id}" },
                     style: "width:100%;justify-content:center") do
                render UI::Icon.new(:refresh, class: ICON_SM)
                plain "Issue refund"
              end
              refund_dialog
            end
            p(class: "#{TYPE_CAPTION} text-center mt-1") do
              plain "Refunds are processed within 5–10 business days."
            end
          end
        end
      end
    end

    def refund_dialog
      dialog(id: "refund-dialog-#{@payment.id}",
             class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[420px] bg-white") do
        div(class: "px-6 py-[22px] border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Confirm refund" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Refund #{@payment.formatted_amount} to the original payment method."
          end
        end
        form(action: payment_refund_path(@payment), method: "post",
             class: "px-6 py-5 flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          div do
            p(class: "#{TYPE_MICRO} mb-1.5") { plain "Reason" }
            select(name: "reason", class: "#{SELECT_FIELD} cursor-pointer") do
              option(value: "requested_by_merchant") { plain "Requested by merchant" }
              option(value: "duplicate")             { plain "Duplicate charge" }
              option(value: "fraudulent")            { plain "Fraudulent transaction" }
              option(value: "customer_request")      { plain "Customer request" }
            end
          end
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary,
                   data: { action: "click->dialog#close", dialog_target_param: "refund-dialog-#{@payment.id}" }) do
              plain "Cancel"
            end
            render UI::Button.new(variant: :danger, type: "submit") do
              render UI::Icon.new(:refresh, class: ICON_SM)
              plain "Confirm refund"
            end
          end
        end
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    # ── Core events card ──────────────────────────────────────────────────────

    def core_events_card
      render UI::Card.new do |c|
        c.header("Payment events")
        c.body(padding: false) do
          div(class: "divide-y divide-gray-50") do
            @events.each_with_index do |ev, i|
              event_row(ev, last: i == @events.length - 1)
            end
          end
        end
      end
    end

    def event_row(ev, last: false)
      name      = (ev["event_type"] || ev["type"] || "unknown").to_s.gsub("_", " ").capitalize
      occurred  = ev["occurred_at"] || ev["inserted_at"]
      ts        = occurred ? Time.parse(occurred).strftime("%d %b %Y, %H:%M:%S UTC") : "—"

      div(class: "flex items-start gap-3 px-5 py-[11px] #{last ? '' : 'border-b border-gray-50'}") do
        div(class: "w-2 h-2 rounded-full flex-shrink-0 mt-[5px]", style: "background:#6366f1")
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain name }
          p(class: "#{TYPE_MONO} text-[11px] text-gray-400 mt-0.5") { plain ts }
          if (meta = ev["metadata"].presence || ev["payload"].presence)
            pre(class: "mt-1.5 text-[10.5px] leading-relaxed bg-gray-50 rounded-lg p-2 overflow-x-auto font-mono text-gray-500 whitespace-pre-wrap break-all") do
              plain JSON.pretty_generate(meta)
            end
          end
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

    def network_logo_label(payment)
      div(class: "flex items-center gap-2") do
        if (logo = payment.method_logo)
          div(class: "w-11 h-6 rounded border border-gray-200 dark:border-white/10 bg-white flex items-center justify-center flex-shrink-0 px-1 overflow-hidden") do
            img(src: asset_path(logo), alt: "", class: "max-h-full max-w-full object-contain")
          end
        end
        span(class: UI::Theme::TYPE_BODY_MD) { plain payment.method_label }
      end
    end

    def customer_value
      @can_view_pii ? (@payment.customer_msisdn || "—") : @payment.masked_msisdn
    end

    def settled_label
      @payment.paid_at ? @payment.paid_at.strftime("%d %b %Y, %H:%M") : "—"
    end
  end
end
