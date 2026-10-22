# frozen_string_literal: true

class SettlementEventsConsumer < ApplicationConsumer
  include IdempotentConsumer

  def consume
    messages.each do |message|
      upsert(message.payload)
    rescue StandardError => e
      Rails.logger.error("SettlementEventsConsumer: #{e.message}")
    end
  end

  private

  def upsert(payload)
    evt = Acl::CoreSettlementEvent.new(payload)
    return unless evt.valid?

    existing = PortalSettlement.find_by(settlement_code: evt.settlement_code)
    return if existing&.last_event_id == evt.event_id && evt.event_id.present?

    attrs = {
      settlement_code:            evt.settlement_code,
      merchant_code:              evt.merchant_code,
      provider_code:              evt.provider_code,
      mode:                       evt.mode,
      aggregate_version:          evt.aggregate_version,
      state:                      evt.state,
      currency:                   evt.currency,
      period_start:               evt.period_start,
      period_end:                 evt.period_end,
      expected_net:               evt.expected_net,
      reported_net:               evt.reported_net,
      variance:                   evt.variance,
      value_date:                 evt.value_date,
      item_count:                 evt.item_count,
      bank_dispatch_ref:          evt.bank_dispatch_ref,
      bank_dispatched_at:         evt.bank_dispatched_at,
      dispatch_approved_by:       evt.dispatch_approved_by,
      dispatch_rejected_by:       evt.dispatch_rejected_by,
      dispatch_rejection_reason:  evt.dispatch_rejection_reason,
      last_event_id:              evt.event_id,
      last_applied_at:            evt.last_applied_at
    }.compact

    PortalSettlement.upsert(attrs, unique_by: :settlement_code, update_only: attrs.keys - [ :settlement_code ])
    update_balance(evt)
  end

  # When a settlement is dispatched, funds move from available → in_transit.
  # When reconciled (bank confirms receipt), in_transit is cleared.
  def update_balance(evt)
    return unless evt.expected_net.to_i.positive?

    case evt.state
    when "dispatched"
      with_idempotency(event_id: "#{evt.settlement_code}:dispatched", consumer: self.class.name) do
        PortalMerchantBalance.apply_delta!(
          merchant_code: evt.merchant_code,
          currency:      evt.currency,
          mode:          evt.mode,
          delta:         { available: -evt.expected_net.to_i, in_transit: evt.expected_net.to_i },
          event_id:      "#{evt.settlement_code}:dispatched"
        )
      end
    when "reconciled"
      with_idempotency(event_id: "#{evt.settlement_code}:reconciled", consumer: self.class.name) do
        PortalMerchantBalance.apply_delta!(
          merchant_code: evt.merchant_code,
          currency:      evt.currency,
          mode:          evt.mode,
          delta:         { in_transit: -evt.expected_net.to_i },
          event_id:      "#{evt.settlement_code}:reconciled"
        )
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[SettlementEventsConsumer] balance update failed: #{e.message}")
  end
end
