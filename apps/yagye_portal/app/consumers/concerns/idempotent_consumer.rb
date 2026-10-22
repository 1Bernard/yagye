# frozen_string_literal: true

# Mixin for Karafka consumers that need DB-level deduplication.
# Upsert-based consumers (payments, settlements) are already idempotent by design.
# COUNTER projections (balances, metrics) are NOT — the same event processed twice
# doubles the count. Use this concern to guard those projection updates.
#
# Usage:
#   include IdempotentConsumer
#
#   def update_balance(event)
#     with_idempotency(event_id: "#{event.public_id}:paid", consumer: self.class.name) do
#       PortalMerchantBalance.apply_delta!(...)
#     end
#   end
module IdempotentConsumer
  # Yields the block exactly once per (event_id, consumer) pair.
  # Concurrent workers racing to process the same event are safe:
  # only one INSERT wins, the other sees a false return and skips the block.
  def with_idempotency(event_id:, consumer:)
    first_time = ProcessedEvent.mark_processed!(event_id: event_id, consumer: consumer)
    yield if first_time
  rescue StandardError => e
    Rails.logger.error("[IdempotentConsumer] #{consumer} event=#{event_id} error=#{e.message}")
    raise
  end
end
