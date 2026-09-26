# frozen_string_literal: true

require "test_helper"

module Payouts
  class UpcomingPayoutQueryTest < ActiveSupport::TestCase
    def payout(attrs = {})
      PortalPayout.create!({
        payout_code:             "PAY-#{SecureRandom.hex(6).upcase}",
        merchant_code:           "MCH-TEST",
        amount:                  500_000,
        currency:                "GHS",
        state:                   "scheduled",
        scheduled_for:           Date.today + 3,
        destination_type:        "bank",
        destination_fingerprint: "GH****1234",
        mode:                    "test",
        last_event_id:           SecureRandom.uuid,
        last_applied_at:         Time.current
      }.merge(attrs))
    end

    # ── merchant view ─────────────────────────────────────────────────────────

    test "returns nil when no in-flight payouts exist" do
      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call
      assert_nil result
    end

    test "returns merchant hash with correct shape for next upcoming payout" do
      payout(amount: 845_000, scheduled_for: Date.today + 3, state: "scheduled")

      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call

      assert_equal :merchant,    result[:kind]
      assert_equal 845_000,      result[:amount]
      assert_equal "GHS",        result[:currency]
      assert_equal Date.today + 3, result[:date]
      assert_equal "scheduled",  result[:state]
      assert_equal 3,            result[:days_until]
    end

    test "picks the earliest scheduled_for when multiple payouts exist" do
      payout(scheduled_for: Date.today + 7, amount: 100_000)
      payout(scheduled_for: Date.today + 2, amount: 200_000)
      payout(scheduled_for: Date.today + 5, amount: 300_000)

      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call

      assert_equal 200_000,      result[:amount]
      assert_equal Date.today + 2, result[:date]
      assert_equal 2,            result[:days_until]
    end

    test "skips payouts with past scheduled_for dates" do
      payout(scheduled_for: Date.today - 1, state: "scheduled")

      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call
      assert_nil result
    end

    test "includes only in-flight states (not paid, returned, failed, cancelled)" do
      payout(state: "paid",      scheduled_for: Date.today + 1)
      payout(state: "returned",  scheduled_for: Date.today + 2)
      payout(state: "failed",    scheduled_for: Date.today + 3)
      payout(state: "cancelled", scheduled_for: Date.today + 4)

      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call
      assert_nil result
    end

    test "includes all in-flight states: scheduled, validating, reserving, submitted" do
      %w[scheduled validating reserving submitted].each_with_index do |st, i|
        payout(state: st, scheduled_for: Date.today + i + 1, merchant_code: "MCH-#{st.upcase}")
      end

      %w[scheduled validating reserving submitted].each do |st|
        r = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-#{st.upcase}")).call
        assert_equal st, r[:state], "Expected in-flight state #{st} to be included"
      end
    end

    test "respects merchant scoping — two merchants see only their own next payout" do
      payout(merchant_code: "MCH-A", amount: 100_000, scheduled_for: Date.today + 1)
      payout(merchant_code: "MCH-B", amount: 999_000, scheduled_for: Date.today + 2)

      result_a = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-A")).call
      result_b = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-B")).call

      assert_equal 100_000, result_a[:amount]
      assert_equal 999_000, result_b[:amount]
    end

    test "days_until is 0 when scheduled_for is today" do
      payout(scheduled_for: Date.today)

      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call
      assert_equal 0, result[:days_until]
    end

    # ── ops view ──────────────────────────────────────────────────────────────

    test "returns nil for ops when no in-flight payouts exist" do
      result = UpcomingPayoutQuery.new(PortalPayout.all, is_ops: true).call
      assert_nil result
    end

    test "returns ops hash with aggregate count and total" do
      payout(merchant_code: "MCH-A", amount: 500_000, scheduled_for: Date.today + 1)
      payout(merchant_code: "MCH-B", amount: 300_000, scheduled_for: Date.today + 2)
      payout(merchant_code: "MCH-C", amount: 200_000, scheduled_for: Date.today + 3)

      result = UpcomingPayoutQuery.new(PortalPayout.all, is_ops: true).call

      assert_equal :ops,         result[:kind]
      assert_equal 3,            result[:count]
      assert_equal 1_000_000,    result[:total]
      assert_equal Date.today + 1, result[:next_date]
      assert_equal 1,            result[:days_until]
    end

    test "ops next_date reflects the earliest scheduled payout across all merchants" do
      payout(merchant_code: "MCH-A", scheduled_for: Date.today + 5)
      payout(merchant_code: "MCH-B", scheduled_for: Date.today + 2)

      result = UpcomingPayoutQuery.new(PortalPayout.all, is_ops: true).call
      assert_equal Date.today + 2, result[:next_date]
    end

    # ── mode filtering ────────────────────────────────────────────────────────

    test "mode filter applied when Current.mode is set — live payouts excluded from test view" do
      live_payout = payout(mode: "live",  scheduled_for: Date.today + 1)
      test_payout = payout(mode: "test",  scheduled_for: Date.today + 2)

      Current.mode = "test"
      result = UpcomingPayoutQuery.new(PortalPayout.for_merchant("MCH-TEST")).call

      assert_not_nil result
      assert_equal test_payout.scheduled_for, result[:date]
    ensure
      Current.mode = nil
    end
  end
end
