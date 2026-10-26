# frozen_string_literal: true

module Payments
  class ShowView < ApplicationComponent
    include UI::Theme

    def initialize(payment:, events: [], can_refund: false, can_view_pii: false, other_payments: [], dispute: nil, reserve_hold: nil)
      @payment        = payment
      @events         = events
      @can_refund     = can_refund
      @can_view_pii   = can_view_pii
      @other_payments = other_payments
      @dispute        = dispute
      @reserve_hold   = reserve_hold
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payments,
        title:      @payment.reference.presence || @payment.core_payment_id&.first(12) || @payment.id.to_s,
        breadcrumbs: [
          { label: "Payments", href: payments_path },
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
        dispute_banner if @dispute
        amount_card
        details_card
        customer_card if @payment.customer_msisdn.present?
        metadata_card
        core_events_card if @events.any?
      end
    end

    def right_column
      div(class: "flex flex-col gap-5") do
        timeline_card
        actions_card if @can_refund && @payment.status == "paid"
        customer_payments_card if @other_payments.any?
      end
    end

    # ── Amount / hero card ────────────────────────────────────────────────────

    def amount_card
      div(class: "#{SURFACE_CARD} px-8 py-7") do
        div(class: "flex items-start justify-between mb-5") do
          div do
            p(class: "#{TYPE_CAPTION} mb-1") { plain "Transaction amount" }
            p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @payment.formatted_amount }
          end
          render UI::StatusBadge.new(@payment.status)
        end

        if @payment.has_fee?
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden mb-3") do
            meta_cell("Gross",   @payment.formatted_amount, mono: true)
            meta_cell("Fee",     @payment.formatted_fee_amount, mono: true)
            meta_cell("Net",     @payment.formatted_net_amount, mono: true)
          end
        end

        if @reserve_hold&.dig("state") == "pending"
          hold_amount    = @reserve_hold["amount"].to_i
          net_minor      = @payment.net_amount || @payment.amount
          available      = net_minor - hold_amount
          currency       = @reserve_hold["currency"] || @payment.currency
          release_date   = begin
                             Time.parse(@reserve_hold["release_at"].to_s).strftime("%-d %b %Y")
                           rescue ArgumentError, TypeError
                             "—"
                           end
          div(class: "grid grid-cols-2 gap-[1px] bg-amber-100 rounded-xl overflow-hidden mb-3") do
            meta_cell("Reserved") do
              div do
                p(class: "text-[12.5px] font-semibold tabular-nums", style: "color:#{AMBER}") do
                  plain format_money(hold_amount, currency: currency)
                end
                p(class: "#{TYPE_CAPTION} mt-[2px]") { plain "Releases #{release_date}" }
              end
            end
            meta_cell("Available to settle") do
              p(class: "text-[12.5px] font-semibold tabular-nums text-gray-900") do
                plain format_money([ available, 0 ].max, currency: currency)
              end
            end
          end
        end

        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          meta_cell("Reference") { copyable_mono(@payment.reference) }
          meta_cell("Method") do
            div(class: "flex items-center gap-2") do
              if (logo = @payment.method_logo)
                div(class: "w-11 h-6 rounded border border-gray-200 dark:border-white/10 bg-white " \
                           "flex items-center justify-center flex-shrink-0 px-1 overflow-hidden") do
                  img(src: asset_path(logo), alt: "", class: "max-h-full max-w-full object-contain")
                end
              end
              span(class: UI::Theme::TYPE_BODY_MD) { plain @payment.payment_method&.humanize || "—" }
            end
          end
          meta_cell("Date",      fmt_date(@payment.created_at))
        end
      end
    end

    # ── Payment details card ──────────────────────────────────────────────────

    def details_card
      render UI::Card.new do |c|
        c.header("Payment details")
        c.body(padding: false) do
          render UI::DetailList.new do |list|
            list.row("Payment ID", stacked: true) { copyable_mono(@payment.core_payment_id) }
            list.row("Type",           @payment.payment_method&.humanize || "—")
            list.row("Network")        { network_logo_label(@payment) }
            list.row("Status")         { render UI::StatusBadge.new(@payment.status) }
            list.row("Created",        fmt_datetime_utc(@payment.created_at))
            list.row("Settled",        settled_label)
            list.row("Merchant") { copyable_mono(@payment.merchant_code) }
            if @payment.fulfilment_type.present?
              list.row("Fulfilment") do
                span(class: "#{BADGE} #{STATUS_NEUTRAL}") do
                  plain @payment.fulfilment_type.capitalize
                end
              end
            end
            list.row("Ship to", @payment.shipping_country) if @payment.shipping_country.present?
            unless @payment.billing_shipping_match.nil?
              list.row("Billing = shipping") do
                if @payment.billing_shipping_match
                  span(class: "text-[12px] font-medium", style: "color:#{GREEN}") { plain "Match ✓" }
                else
                  span(class: "text-[12px] font-medium", style: "color:#{AMBER}") { plain "Mismatch ✗" }
                end
              end
            end
          end
        end
      end
    end

    # ── Customer card ─────────────────────────────────────────────────────────

    def customer_card
      msisdn  = @can_view_pii ? @payment.customer_msisdn : @payment.masked_msisdn
      email   = @can_view_pii ? @payment.customer_email  : nil
      logo    = Payment::PROVIDER_LOGOS[@payment.provider.to_s]
      label   = Payment::PROVIDERS.fetch(@payment.provider.to_s, nil)

      render UI::Card.new do |c|
        c.header("Customer")
        c.body do
          div(class: "flex items-center justify-between gap-3") do
            div(class: "flex items-center gap-3 min-w-0") do
              if logo
                div(class: "w-8 h-8 rounded-xl bg-white border border-gray-100 flex items-center justify-center flex-shrink-0 overflow-hidden p-0.5") do
                  img(src: asset_path(logo), alt: label.to_s, class: "w-full h-full object-contain")
                end
              else
                div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                    style: "background:#{TINT_GRAY}") do
                  span(class: "flex w-4 h-4 text-gray-500") { render UI::Icon.new(:user, class: "w-full h-full") }
                end
              end
              div(class: "min-w-0") do
                p(class: "#{TYPE_BODY_MD} font-mono truncate") { plain msisdn || "—" }
                p(class: TYPE_CAPTION) { plain email } if email.present?
                p(class: TYPE_CAPTION) { plain label } if label.present?
              end
            end
            a(href: customers_path(q: @payment.customer_msisdn),
              class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 " \
                     "rounded-[9px] text-[12.5px] font-medium text-gray-600 bg-white " \
                     "no-underline hover:border-gray-400 transition-colors flex-shrink-0") do
              render UI::Icon.new(:eye, class: "w-3 h-3")
              plain "View"
            end
          end
        end
      end
    end

    # ── Metadata card ─────────────────────────────────────────────────────────

    def metadata_card
      return if @payment.metadata.blank?

      render UI::Card.new do |c|
        c.header("Metadata")
        c.body do
          pre(class: "#{TYPE_MONO} text-[11.5px] bg-gray-50 rounded-xl p-[14px] overflow-x-auto leading-relaxed whitespace-pre-wrap break-all") do
            plain JSON.pretty_generate(@payment.metadata)
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
            a(href: refund_modal_payment_path(@payment),
              class: "#{BTN_DANGER} w-full justify-center",
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:refresh, class: ICON_SM)
              plain "Issue refund"
            end
            p(class: "#{TYPE_CAPTION} text-center mt-1") do
              plain "Refunds are processed within 5–10 business days."
            end
          end
        end
      end
    end

    # ── Customer's other payments ─────────────────────────────────────────────

    def customer_payments_card
      render UI::Card.new do |c|
        c.header("Other payments from this customer")
        c.body(padding: false) do
          div(class: "divide-y divide-gray-50") do
            @other_payments.each_with_index do |p, i|
              last = i == @other_payments.length - 1
              a(href: payment_path(p),
                class: "flex items-center justify-between px-5 py-[11px] hover:bg-gray-50 transition-colors no-underline #{last ? '' : 'border-b border-gray-50'}") do
                div(class: "flex-1 min-w-0") do
                  span(class: "block #{TYPE_MONO} text-[11.5px] truncate") { plain p.reference.presence || p.core_payment_id&.first(12) || "—" }
                  span(class: "block #{TYPE_CAPTION} mt-px") { plain fmt_date(p.created_at) }
                end
                div(class: "flex items-center gap-2 flex-shrink-0") do
                  span(class: "text-[13px] font-semibold text-gray-900 tabular-nums") { plain p.formatted_amount }
                  render UI::StatusBadge.new(p.status)
                end
              end
            end
          end
        end
      end
    end

    # ── Dispute banner ────────────────────────────────────────────────────────

    def dispute_banner
      href = @dispute ? dispute_path(@dispute) : disputes_path
      render UI::Notice.new(
        title:        "Dispute open",
        body:         "A chargeback has been raised against this payment.",
        variant:      :warning,
        size:         :lg,
        icon:         :flag,
        action_label: "View dispute →",
        action_href:  href
      )
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    # ── Core events card ──────────────────────────────────────────────────────

    def core_events_card
      render UI::Card.new do |c|
        c.header("Payment events") do
          a(href: developers_path(tab: "deliveries"),
            class: "#{TYPE_CAPTION} hover:underline no-underline",
            style: "color:#{BRAND}") do
            plain "Webhook logs →"
          end
        end
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
        div(class: "w-2 h-2 rounded-full flex-shrink-0 mt-[5px]", style: "background:#{BRAND}")
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

    EVENT_TIMELINE_MAP = {
      "payment.initiated"  => [ "Payment initiated", BRAND  ],
      "payment.processing" => [ "Processing",        AMBER  ],
      "payment.succeeded"  => [ "Payment settled",   GREEN  ],
      "payment.failed"     => [ "Payment failed",    RED    ],
      "payment.refunded"   => [ "Refunded",          AMBER  ],
      "payment.captured"   => [ "Captured",          GREEN  ],
      "payment.cancelled"  => [ "Cancelled",         "#9CA3AF" ]
    }.freeze

    def timeline_events
      if @events.any?
        @events.filter_map { |ev|
          cfg = EVENT_TIMELINE_MAP[(ev["event_type"] || ev["type"]).to_s]
          next unless cfg
          raw = ev["occurred_at"] || ev["inserted_at"]
          ts  = raw ? Time.parse(raw) : nil
          [ cfg[0], ts, cfg[1] ]
        }.sort_by { |_, ts, _| ts || Time.at(0) }
      else
        fallback_timeline
      end
    end

    def fallback_timeline
      events = [ [ "Payment initiated", @payment.created_at, BRAND ] ]
      events << [ "Payment settled",  @payment.paid_at,    GREEN ] if @payment.paid_at.present?
      events << [ "Payment failed",   @payment.updated_at, RED   ] if @payment.status == "failed"
      events << [ "Refunded",         @payment.updated_at, AMBER ] if @payment.status == "refunded"
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

    def settled_label
      fmt_datetime_utc(@payment.paid_at)
    end
  end
end
