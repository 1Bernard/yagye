# frozen_string_literal: true

require "test_helper"

class SettlementEventsConsumerTest < ActiveSupport::TestCase
  # Minimal valid Core settlement event payload.
  def base_payload(overrides = {})
    {
      "settlement_code"  => "SET-#{SecureRandom.hex(4).upcase}",
      "merchant_code"    => "MCH-0001",
      "provider_code"    => "mtn_momo",
      "mode"             => "live",
      "state"            => "initiated",
      "currency"         => "GHS",
      "period_start"     => 2.days.ago.iso8601,
      "period_end"       => 1.day.ago.iso8601,
      "expected_net"     => 50_000,
      "item_count"       => 10,
      "aggregate_version" => 1,
      "event_id"         => SecureRandom.uuid,
      "timestamp"        => Time.current.iso8601
    }.merge(overrides)
  end

  def consume(payload)
    SettlementEventsConsumer.new.send(:upsert, payload)
  end

  # ── Creates a new record ──────────────────────────────────────────────────

  test "creates a PortalSettlement when none exists" do
    payload = base_payload
    assert_difference "PortalSettlement.count", 1 do
      consume(payload)
    end
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal "MCH-0001",  s.merchant_code
    assert_equal "mtn_momo",  s.provider_code
    assert_equal "initiated",  s.state
    assert_equal 50_000,       s.expected_net
    assert_equal 10,           s.item_count
  end

  # ── Updates an existing record ────────────────────────────────────────────

  test "updates existing PortalSettlement without creating a duplicate" do
    settlement = create(:portal_settlement, settlement_code: "SET-EXIST", state: "initiated")
    payload = base_payload("settlement_code" => "SET-EXIST", "state" => "dispatched",
                           "bank_dispatch_ref" => "BANK-REF-001",
                           "event_id" => SecureRandom.uuid)

    assert_no_difference "PortalSettlement.count" do
      consume(payload)
    end
    assert_equal "dispatched",   settlement.reload.state
    assert_equal "BANK-REF-001", settlement.bank_dispatch_ref
  end

  # ── Invalid payload ───────────────────────────────────────────────────────

  test "skips processing when settlement_code is missing" do
    assert_no_difference "PortalSettlement.count" do
      consume(base_payload.except("settlement_code"))
    end
  end

  test "skips processing when settlement_code is blank" do
    assert_no_difference "PortalSettlement.count" do
      consume(base_payload("settlement_code" => ""))
    end
  end

  # ── Stale event deduplication ─────────────────────────────────────────────

  test "skips a duplicate event with the same event_id" do
    event_id = SecureRandom.uuid
    settlement = create(:portal_settlement, settlement_code: "SET-DEDUP",
                        state: "initiated", last_event_id: event_id)
    consume(base_payload("settlement_code" => "SET-DEDUP", "state" => "dispatched",
                         "event_id" => event_id))
    assert_equal "initiated", settlement.reload.state
  end

  # ── Field mapping aliases ─────────────────────────────────────────────────

  test "accepts net_amount as fallback for expected_net" do
    payload = base_payload.except("expected_net").merge("net_amount" => 25_000)
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal 25_000, s.expected_net
  end

  test "accepts payment_count as fallback for item_count" do
    payload = base_payload.except("item_count").merge("payment_count" => 7)
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal 7, s.item_count
  end

  test "mode defaults to test when missing" do
    payload = base_payload.except("mode")
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal "test", s.mode
  end

  test "currency defaults to GHS when missing" do
    payload = base_payload.except("currency")
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal "GHS", s.currency
  end

  # ── Optional fields ───────────────────────────────────────────────────────

  test "persists dispatch approval fields when present" do
    payload = base_payload("state" => "dispatched",
                           "bank_dispatch_ref"         => "REF-9999",
                           "dispatch_approved_by"      => "manager@yagye.com",
                           "dispatch_rejection_reason" => nil)
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal "REF-9999",          s.bank_dispatch_ref
    assert_equal "manager@yagye.com", s.dispatch_approved_by
  end

  test "persists dispatch rejection fields when present" do
    payload = base_payload("state" => "rejected",
                           "dispatch_rejected_by"      => "manager@yagye.com",
                           "dispatch_rejection_reason" => "Incorrect net amount")
    consume(payload)
    s = PortalSettlement.find_by!(settlement_code: payload["settlement_code"])
    assert_equal "manager@yagye.com",    s.dispatch_rejected_by
    assert_equal "Incorrect net amount", s.dispatch_rejection_reason
  end

  # ── Balance projection — dispatched ──────────────────────────────────────

  test "decrements available and increments in_transit on dispatched state" do
    code    = "SET-DISPATCH-BAL"
    payload = base_payload("settlement_code" => code,
                           "state"           => "dispatched",
                           "expected_net"    => 10_000,
                           "merchant_code"   => "MCH-BAL-1",
                           "event_id"        => "evt-dispatch-#{code}")

    # Seed a starting balance so apply_delta! has a row to update.
    PortalMerchantBalance.apply_delta!(
      merchant_code: "MCH-BAL-1", currency: "GHS", mode: "live",
      delta: { available: 20_000 }, event_id: "seed-#{code}"
    )

    consume(payload)

    bal = PortalMerchantBalance.find_by!(merchant_code: "MCH-BAL-1", currency: "GHS", mode: "live")
    assert_equal 10_000, bal.available
    assert_equal 10_000, bal.in_transit
  end

  test "decrements in_transit on reconciled state" do
    code    = "SET-RECONCILE-BAL"
    payload = base_payload("settlement_code" => code,
                           "state"           => "reconciled",
                           "expected_net"    => 8_000,
                           "merchant_code"   => "MCH-BAL-2",
                           "event_id"        => "evt-recon-#{code}")

    PortalMerchantBalance.apply_delta!(
      merchant_code: "MCH-BAL-2", currency: "GHS", mode: "live",
      delta: { in_transit: 8_000 }, event_id: "seed-#{code}"
    )

    consume(payload)

    bal = PortalMerchantBalance.find_by!(merchant_code: "MCH-BAL-2", currency: "GHS", mode: "live")
    assert_equal 0, bal.in_transit
  end

  # ── Balance idempotency ───────────────────────────────────────────────────

  test "balance projection is applied only once for the same dispatched event" do
    code     = "SET-IDEMPOTENT"
    event_id = "evt-idempotent-dispatch"
    payload  = base_payload("settlement_code" => code,
                            "state"           => "dispatched",
                            "expected_net"    => 5_000,
                            "merchant_code"   => "MCH-BAL-3",
                            "event_id"        => event_id)

    PortalMerchantBalance.apply_delta!(
      merchant_code: "MCH-BAL-3", currency: "GHS", mode: "live",
      delta: { available: 15_000 }, event_id: "seed-#{code}"
    )

    consume(payload)  # first time — applies balance
    # second call: settlement row has same last_event_id, skipped entirely
    consume(payload)

    bal = PortalMerchantBalance.find_by!(merchant_code: "MCH-BAL-3", currency: "GHS", mode: "live")
    assert_equal 10_000, bal.available, "balance should only be decremented once"
    assert_equal 5_000,  bal.in_transit
  end

  test "balance is not touched when expected_net is zero" do
    payload = base_payload("state" => "dispatched", "expected_net" => 0,
                           "merchant_code" => "MCH-BAL-ZERO")
    consume(payload)
    assert_nil PortalMerchantBalance.find_by(merchant_code: "MCH-BAL-ZERO")
  end

  test "balance is not touched for states other than dispatched or reconciled" do
    payload = base_payload("state" => "initiated", "expected_net" => 5_000,
                           "merchant_code" => "MCH-BAL-NOOP")
    consume(payload)
    assert_nil PortalMerchantBalance.find_by(merchant_code: "MCH-BAL-NOOP")
  end
end
