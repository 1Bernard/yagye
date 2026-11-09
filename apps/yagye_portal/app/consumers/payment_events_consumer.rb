# frozen_string_literal: true

class PaymentEventsConsumer < ApplicationConsumer
  include IdempotentConsumer

  def consume
    messages.each do |message|
      event = Acl::CorePaymentEvent.new(message.payload)
      next unless event.valid?
      upsert_payment(event)
    end
  end

  private

  def upsert_payment(event)
    attrs = {
      merchant_code:   event.merchant_code,
      reference:       event.reference,
      customer_msisdn: event.customer_msisdn,
      customer_email:  event.customer_email,
      amount:          event.amount.nonzero?,
      currency:        event.currency.presence,
      status:          event.status.presence,
      provider:        event.provider,
      payment_method:  event.payment_method,
      description:     event.description,
      metadata:        event.metadata,
      paid_at:                event.paid_at,
      settled_at:             event.settled_at,
      mode:                   event.mode,
      fee_amount:             event.fee_amount,
      net_amount:             event.net_amount,
      fulfilment_type:        event.fulfilment_type,
      shipping_country:       event.shipping_country,
      billing_shipping_match: event.billing_shipping_match,
      risk_decision:          event.risk_decision,
      risk_score:             event.risk_score,
      risk_flagged_at:        event.risk_flagged_at
    }.compact

    Payment.find_or_initialize_by(core_payment_id: event.public_id).tap do |p|
      p.assign_attributes(attrs)
      p.save!
      broadcast_to_feed(p)
      broadcast_status_update(p)
      notify_payment(p, event)
      update_balance(event) if event.status == "paid"
      deduct_refund_balance(p, event) if event.status == "refunded"
      broadcast_risk_badge if event.event_type == "payment.risk_flagged"
    end
  end

  def update_balance(event)
    return unless event.net_amount.to_i.positive?

    with_idempotency(event_id: "#{event.public_id}:balance", consumer: self.class.name) do
      PortalMerchantBalance.apply_delta!(
        merchant_code: event.merchant_code,
        currency:      event.currency,
        mode:          event.mode,
        delta:         { available: event.net_amount.to_i },
        event_id:      "#{event.public_id}:balance"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] balance update failed: #{e.message}")
  end

  def deduct_refund_balance(payment, event)
    # Use the stored net_amount from the portal payment record — this was set when
    # the payment originally succeeded and is authoritative for what the merchant earned.
    amount = payment.net_amount || payment.amount
    return unless amount.to_i.positive?

    with_idempotency(event_id: "#{event.public_id}:refund_balance", consumer: self.class.name) do
      PortalMerchantBalance.apply_delta!(
        merchant_code: payment.merchant_code,
        currency:      payment.currency,
        mode:          payment.mode,
        delta:         { available: -amount },
        event_id:      "#{event.public_id}:refund_balance"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] refund balance deduction failed: #{e.message}")
  end

  def broadcast_to_feed(payment)
    stream = "dashboard_feed_#{payment.merchant_code}_#{payment.portal_mode}"
    html   = ApplicationController.render(
      Dashboard::FeedRowComponent.new(payment: payment),
      layout: false
    )
    Turbo::StreamsChannel.broadcast_prepend_to(
      stream,
      target: "payment-feed",
      html:   html
    )
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] feed broadcast failed: #{e.message}")
  end

  def notify_payment(payment, event)
    case payment.status
    when "paid"
      amt = payment.amount ? format_minor_units(payment.amount, payment.currency) : ""
      Notifications::DeliveryService.schedule(
        merchant_code:   payment.merchant_code,
        event_type:      "payment_success",
        title:           "Payment received",
        body:            "#{amt} from #{payment.customer_msisdn || payment.customer_email || 'a customer'} · Ref: #{payment.reference}",
        link:            "/payments/#{payment.id}",
        metadata:        { payment_id: payment.id, reference: payment.reference },
        mode:            event.mode,
        urgency:         "info",
        source_event_id: "#{event.public_id}:payment_success"
      )
      dispatch_customer_receipt(event)
    when "failed"
      Notifications::DeliveryService.schedule(
        merchant_code:   payment.merchant_code,
        event_type:      "payment_failed",
        title:           "Payment failed",
        body:            "Ref: #{payment.reference} — #{payment.provider || 'unknown provider'}",
        link:            "/payments/#{payment.id}",
        metadata:        { payment_id: payment.id, reference: payment.reference },
        mode:            event.mode,
        urgency:         "warning",
        source_event_id: "#{event.public_id}:payment_failed"
      )
    when "refunded"
      amt = payment.amount ? format_minor_units(payment.amount, payment.currency) : ""
      Notifications::DeliveryService.schedule(
        merchant_code:   payment.merchant_code,
        event_type:      "payment_refunded",
        title:           "Refund processed",
        body:            "#{amt} refunded · Ref: #{payment.reference}",
        link:            "/payments/#{payment.id}",
        metadata:        { payment_id: payment.id, reference: payment.reference },
        mode:            event.mode,
        urgency:         "info",
        source_event_id: "#{event.public_id}:payment_refunded"
      )
    when "chargebacked"
      amt = payment.amount ? format_minor_units(payment.amount, payment.currency) : ""
      Notifications::DeliveryService.schedule(
        merchant_code:   payment.merchant_code,
        event_type:      "payment_chargebacked",
        title:           "Chargeback received",
        body:            "#{amt} chargebacked · Ref: #{payment.reference}",
        link:            "/payments/#{payment.id}",
        metadata:        { payment_id: payment.id, reference: payment.reference },
        mode:            event.mode,
        urgency:         "warning",
        source_event_id: "#{event.public_id}:payment_chargebacked"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] notify failed: #{e.message}")
  end

  def broadcast_status_update(payment)
    stream  = "payments_#{payment.merchant_code}_#{payment.portal_mode}"
    target  = "payment-status-#{payment.id}"
    badge   = UI::StatusBadge.new(status: payment.status).call
    html    = "<div id=\"#{target}\">#{badge}</div>"
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: target, html: html)
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] status broadcast failed: #{e.message}")
  end

  def dispatch_customer_receipt(event)
    receipt_base = ENV.fetch("RECEIPT_BASE_URL", "https://app.yagye.io")
    receipt_url  = "#{receipt_base}/r/#{event.public_id}"
    amount_ghs   = format("GH₵%.2f", event.amount / 100.0)
    ref_short    = event.public_id.to_s.last(8).upcase

    if event.customer_msisdn.present?
      content = "#{amount_ghs} payment confirmed. Ref: #{ref_short}. Receipt: #{receipt_url}"
      content = content.first(157) + "..." if content.length > 160
      SmsNotifierJob.perform_later(to: event.customer_msisdn, content: content, tag: "receipt")
    end

    if event.customer_email.present?
      ReceiptMailer.payment_confirmed(
        to:            event.customer_email,
        amount:        event.amount,
        currency:      event.currency,
        public_id:     event.public_id,
        merchant_code: event.merchant_code,
        method:        event.payment_method,
        paid_at:       event.paid_at.to_s
      ).deliver_later
    end
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] receipt dispatch failed: #{e.message}")
  end

  def broadcast_risk_badge
    count = Payment.where(risk_decision: "review").count
    html  = risk_badge_html(count)
    Turbo::StreamsChannel.broadcast_replace_to(
      "risk_ops_global",
      target: "risk-nav-badge",
      html:   html
    )
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] risk badge broadcast failed: #{e.message}")
  end

  def risk_badge_html(count)
    if count.positive?
      style = "display:inline-flex;align-items:center;justify-content:center;min-width:16px;" \
              "height:16px;border-radius:8px;background:#ef4444;color:#fff;font-size:9px;" \
              "font-weight:700;padding:0 4px;margin-left:4px;flex-shrink:0;"
      %(<span id="risk-nav-badge" style="#{style}">#{count}</span>)
    else
      %(<span id="risk-nav-badge" style="display:none;"></span>)
    end
  end

  def format_minor_units(minor_units, currency_code = "GHS")
    return "—" if minor_units.nil?
    n = minor_units.to_f / 100
    whole, frac = sprintf("%.2f", n).split(".")
    "#{currency_code} #{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}.#{frac}"
  end
end
