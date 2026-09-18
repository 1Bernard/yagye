# frozen_string_literal: true

require "test_helper"

module Acl
  class CorePaymentEventTest < ActiveSupport::TestCase
    # Minimal valid payload.
    def build_payload(overrides = {})
      {
        "public_id"     => "pay_abc123",
        "merchant_code" => "MCH-0001",
        "state"         => "succeeded",
        "amount"        => 5000,
        "currency"      => "GHS",
        "mode"          => "live",
        "provider"      => "mtn_momo"
      }.merge(overrides)
    end

    # ── valid? ────────────────────────────────────────────────────────────────

    test "valid? is true when public_id is present" do
      event = CorePaymentEvent.new(build_payload)
      assert event.valid?
    end

    test "valid? is false when public_id is missing" do
      event = CorePaymentEvent.new(build_payload.except("public_id"))
      refute event.valid?
    end

    test "valid? is false when public_id is blank" do
      event = CorePaymentEvent.new(build_payload("public_id" => ""))
      refute event.valid?
    end

    # ── state → status translation ────────────────────────────────────────────

    test "succeeded maps to paid" do
      event = CorePaymentEvent.new(build_payload("state" => "succeeded"))
      assert_equal "paid", event.status
    end

    test "authorised maps to processing" do
      event = CorePaymentEvent.new(build_payload("state" => "authorised"))
      assert_equal "processing", event.status
    end

    test "chargebacked maps to refunded" do
      event = CorePaymentEvent.new(build_payload("state" => "chargebacked"))
      assert_equal "refunded", event.status
    end

    test "unknown state passes through unchanged" do
      event = CorePaymentEvent.new(build_payload("state" => "unknown_state"))
      assert_equal "unknown_state", event.status
    end

    # ── fulfilment_type ───────────────────────────────────────────────────────

    test "fulfilment_type returns value when present" do
      event = CorePaymentEvent.new(build_payload("fulfilment_type" => "physical"))
      assert_equal "physical", event.fulfilment_type
    end

    test "fulfilment_type returns nil when blank" do
      event = CorePaymentEvent.new(build_payload("fulfilment_type" => ""))
      assert_nil event.fulfilment_type
    end

    test "fulfilment_type returns nil when key absent" do
      event = CorePaymentEvent.new(build_payload)
      assert_nil event.fulfilment_type
    end

    # ── shipping_country ──────────────────────────────────────────────────────

    test "shipping_country returns value when present" do
      event = CorePaymentEvent.new(build_payload("shipping_country" => "GH"))
      assert_equal "GH", event.shipping_country
    end

    test "shipping_country returns nil when blank" do
      event = CorePaymentEvent.new(build_payload("shipping_country" => ""))
      assert_nil event.shipping_country
    end

    # ── billing_shipping_match (boolean — false is a valid value) ─────────────

    test "billing_shipping_match returns true when payload is true" do
      event = CorePaymentEvent.new(build_payload("billing_shipping_match" => true))
      assert_equal true, event.billing_shipping_match
    end

    test "billing_shipping_match returns false when payload is false" do
      event = CorePaymentEvent.new(build_payload("billing_shipping_match" => false))
      assert_equal false, event.billing_shipping_match
    end

    test "billing_shipping_match returns nil when key is absent" do
      event = CorePaymentEvent.new(build_payload)
      assert_nil event.billing_shipping_match
    end

    test "billing_shipping_match returns nil when value is nil" do
      event = CorePaymentEvent.new(build_payload("billing_shipping_match" => nil))
      assert_nil event.billing_shipping_match
    end
  end
end
