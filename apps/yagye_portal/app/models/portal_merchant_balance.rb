# frozen_string_literal: true

class PortalMerchantBalance < ApplicationRecord
  self.primary_key = [ :merchant_code, :currency, :mode ]

  validates :merchant_code, :currency, :mode, :last_applied_at, presence: true

  def self.for_merchant(merchant_code, mode: nil)
    scope = where(merchant_code: merchant_code)
    mode ? scope.where(mode: mode) : scope
  end

  # Atomically increments balance columns for a given (merchant, currency, mode) key.
  # +delta+ is a hash of column => signed_integer_amount (negative = deduct).
  # Uses INSERT … ON CONFLICT DO UPDATE with arithmetic to prevent lost updates.
  def self.apply_delta!(merchant_code:, currency:, mode:, delta:, event_id:)
    conn = connection
    sql = <<~SQL
      INSERT INTO portal_merchant_balances
        (merchant_code, currency, mode, last_applied_at,
         available, pending, reserved, in_transit, last_event_id)
      VALUES (
        #{conn.quote(merchant_code)},
        #{conn.quote(currency)},
        #{conn.quote(mode)},
        NOW(),
        #{delta.fetch(:available, 0).to_i},
        #{delta.fetch(:pending, 0).to_i},
        #{delta.fetch(:reserved, 0).to_i},
        #{delta.fetch(:in_transit, 0).to_i},
        #{conn.quote(event_id)}
      )
      ON CONFLICT (merchant_code, currency, mode) DO UPDATE SET
        available       = portal_merchant_balances.available       + EXCLUDED.available,
        pending         = portal_merchant_balances.pending         + EXCLUDED.pending,
        reserved        = portal_merchant_balances.reserved        + EXCLUDED.reserved,
        in_transit      = portal_merchant_balances.in_transit      + EXCLUDED.in_transit,
        last_event_id   = EXCLUDED.last_event_id,
        last_applied_at = NOW()
    SQL
    conn.execute(sql)
  end
end
