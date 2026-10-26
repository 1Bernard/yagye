# frozen_string_literal: true

require "test_helper"

class PayoutEventsConsumerTest < ActiveSupport::TestCase
  def base_payload(overrides = {})
    {
      "payout_code"            => "PAY-#{SecureRandom.hex(4).upcase}",
      "merchant_code"          => "MCH-0001",
      "mode"                   => "live",
      "state"                  => "scheduled",
      "amount"                 => 50_000,
      "currency"               => "GHS",
      "destination_type"       => "mobile_money",
      "destination_fingerprint" => "mtn:0241000001",
      "scheduled_for"          => Date.tomorrow.iso8601,
      "aggregate_version"      => 1,
      "event_id"               => SecureRandom.uuid,
      "timestamp"              => Time.current.iso8601
    }.merge(overrides)
  end

  def consume(payload)
    PayoutEventsConsumer.new.send(:upsert, payload)
  end

  # ── Creates a new record ──────────────────────────────────────────────────

  test "creates a PortalPayout when none exists" do
    payload = base_payload
    assert_difference "PortalPayout.count", 1 do
      consume(payload)
    end
    p = PortalPayout.find_by!(payout_code: payload["payout_code"])
    assert_equal "MCH-0001",       p.merchant_code
    assert_equal "scheduled",      p.state
    assert_equal 50_000,           p.amount
    assert_equal "mobile_money",   p.destination_type
    assert_equal "mtn:0241000001", p.destination_fingerprint
  end

  # ── Updates an existing record ────────────────────────────────────────────

  test "updates existing PortalPayout without creating a duplicate" do
    payout = create(:portal_payout, payout_code: "PAY-EXIST", state: "scheduled")
    payload = base_payload("payout_code" => "PAY-EXIST", "state" => "dispatched",
                           "event_id" => SecureRandom.uuid)

    assert_no_difference "PortalPayout.count" do
      consume(payload)
    end
    assert_equal "dispatched", payout.reload.state
  end

  # ── Invalid payload ───────────────────────────────────────────────────────

  test "skips processing when payout_code is missing and public_id is also absent" do
    assert_no_difference "PortalPayout.count" do
      consume(base_payload.except("payout_code"))
    end
  end

  test "skips processing when payout_code is blank" do
    assert_no_difference "PortalPayout.count" do
      consume(base_payload("payout_code" => ""))
    end
  end

  # ── Stale event deduplication ─────────────────────────────────────────────

  test "skips a duplicate event with the same event_id" do
    event_id = SecureRandom.uuid
    payout = create(:portal_payout, payout_code: "PAY-DEDUP",
                    state: "scheduled", last_event_id: event_id)
    consume(base_payload("payout_code" => "PAY-DEDUP", "state" => "dispatched",
                         "event_id" => event_id))
    assert_equal "scheduled", payout.reload.state
  end

  # ── Field mapping aliases ─────────────────────────────────────────────────

  test "accepts public_id as fallback for payout_code" do
    payload = base_payload.except("payout_code").merge("public_id" => "PAY-ALIAS-001")
    assert_difference "PortalPayout.count", 1 do
      consume(payload)
    end
    assert PortalPayout.exists?(payout_code: "PAY-ALIAS-001")
  end

  test "mode defaults to test when missing" do
    payload = base_payload.except("mode")
    consume(payload)
    assert_equal "test", PortalPayout.find_by!(payout_code: payload["payout_code"]).mode
  end

  test "currency defaults to GHS when missing" do
    payload = base_payload.except("currency")
    consume(payload)
    assert_equal "GHS", PortalPayout.find_by!(payout_code: payload["payout_code"]).currency
  end

  # ── Optional fields ───────────────────────────────────────────────────────

  test "persists failure_code when present" do
    payload = base_payload("state" => "failed", "failure_code" => "insufficient_funds")
    consume(payload)
    p = PortalPayout.find_by!(payout_code: payload["payout_code"])
    assert_equal "insufficient_funds", p.failure_code
  end

  test "leaves failure_code nil when absent — compact drops the key" do
    payload = base_payload
    consume(payload)
    p = PortalPayout.find_by!(payout_code: payload["payout_code"])
    # compact removes nil failure_code — existing DB default (nil) is untouched
    assert_nil p.failure_code
  end

  test "does not overwrite existing failure_code when key is absent from new event" do
    payout = create(:portal_payout, payout_code: "PAY-FC", failure_code: "bank_timeout")
    # Event without failure_code — compact drops it, so existing value must survive
    consume(base_payload("payout_code" => "PAY-FC", "event_id" => SecureRandom.uuid))
    assert_equal "bank_timeout", payout.reload.failure_code
  end

  # ── State transitions ─────────────────────────────────────────────────────

  test "transitions from scheduled to dispatched" do
    payout = create(:portal_payout, payout_code: "PAY-STATE", state: "scheduled")
    consume(base_payload("payout_code" => "PAY-STATE", "state" => "dispatched",
                         "event_id" => SecureRandom.uuid))
    assert_equal "dispatched", payout.reload.state
  end

  test "transitions from dispatched to completed" do
    payout = create(:portal_payout, payout_code: "PAY-DONE", state: "dispatched")
    consume(base_payload("payout_code" => "PAY-DONE", "state" => "completed",
                         "event_id" => SecureRandom.uuid))
    assert_equal "completed", payout.reload.state
  end

  test "transitions from scheduled to failed with failure_code" do
    payout = create(:portal_payout, payout_code: "PAY-FAIL", state: "scheduled")
    consume(base_payload("payout_code" => "PAY-FAIL", "state" => "failed",
                         "failure_code" => "bank_rejected", "event_id" => SecureRandom.uuid))
    payout.reload
    assert_equal "failed",        payout.state
    assert_equal "bank_rejected", payout.failure_code
  end
end
