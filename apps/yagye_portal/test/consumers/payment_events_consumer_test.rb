# frozen_string_literal: true

require "test_helper"

class PaymentEventsConsumerTest < ActiveSupport::TestCase
  # Minimal valid Core payment payload.
  def base_payload(overrides = {})
    {
      "public_id"     => "pay_test_#{SecureRandom.hex(4)}",
      "merchant_code" => "MCH-0001",
      "state"         => "succeeded",
      "amount"        => 5000,
      "currency"      => "GHS",
      "mode"          => "live",
      "provider"      => "mtn_momo",
      "method"        => "mobile_money",
      "metadata"      => {}
    }.merge(overrides)
  end

  def consume(payload)
    event = Acl::CorePaymentEvent.new(payload)
    # Invoke the private upsert_payment directly to test in isolation,
    # without standing up a full Karafka batch harness.
    PaymentEventsConsumer.new.tap do |c|
      c.send(:upsert_payment, event)
    end
  end

  # ── Creates a new record ──────────────────────────────────────────────────

  test "creates a payment record when none exists" do
    payload = base_payload
    assert_difference "Payment.count", 1 do
      consume(payload)
    end
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_equal "MCH-0001",    p.merchant_code
    assert_equal "paid",        p.status
    assert_equal 5000,          p.amount
  end

  # ── Updates an existing record ────────────────────────────────────────────

  test "updates an existing payment record without creating a duplicate" do
    payment = create(:payment, core_payment_id: "pay_existing", status: "processing")
    payload = base_payload("public_id" => "pay_existing", "state" => "succeeded")

    assert_no_difference "Payment.count" do
      consume(payload)
    end
    assert_equal "paid", payment.reload.status
  end

  # ── fulfilment_type ───────────────────────────────────────────────────────

  test "persists fulfilment_type when present in payload" do
    payload = base_payload("fulfilment_type" => "physical")
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_equal "physical", p.fulfilment_type
  end

  test "leaves fulfilment_type nil when absent from payload" do
    payload = base_payload
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_nil p.fulfilment_type
  end

  test "leaves fulfilment_type nil when payload value is blank" do
    payload = base_payload("fulfilment_type" => "")
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_nil p.fulfilment_type
  end

  # ── shipping_country ──────────────────────────────────────────────────────

  test "persists shipping_country when present in payload" do
    payload = base_payload("shipping_country" => "GH")
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_equal "GH", p.shipping_country
  end

  test "leaves shipping_country nil when absent from payload" do
    payload = base_payload
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_nil p.shipping_country
  end

  # ── billing_shipping_match ────────────────────────────────────────────────

  test "persists billing_shipping_match true when payload is true" do
    payload = base_payload("billing_shipping_match" => true)
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_equal true, p.billing_shipping_match
  end

  test "persists billing_shipping_match false when payload is false" do
    payload = base_payload("billing_shipping_match" => false)
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_equal false, p.billing_shipping_match
  end

  test "leaves billing_shipping_match nil when key absent from payload" do
    payload = base_payload
    consume(payload)
    p = Payment.find_by!(core_payment_id: payload["public_id"])
    assert_nil p.billing_shipping_match
  end

  test "does not overwrite existing billing_shipping_match with nil when key absent" do
    payment = create(:payment, core_payment_id: "pay_bsm", billing_shipping_match: true)
    # New event without billing_shipping_match key — compact means key is dropped,
    # so existing value must survive.
    payload = base_payload("public_id" => "pay_bsm")
    consume(payload)
    assert_equal true, payment.reload.billing_shipping_match
  end
end
