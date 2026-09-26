# frozen_string_literal: true

require "test_helper"

module Payments
  class NetworkHealthQueryTest < ActiveSupport::TestCase
    # ── helpers ────────────────────────────────────────────────────────────────

    # Creates n paid + f failed MTN MoMo payments in the last 30-minute window.
    def mtn(paid:, failed:, merchant_code: "MCH-TEST")
      paid.times   { create(:payment, provider: "mtn_momo",     status: "paid",   merchant_code:, created_at: 10.minutes.ago) }
      failed.times { create(:payment, provider: "mtn_momo",     status: "failed", merchant_code:, created_at: 10.minutes.ago) }
    end

    def telecel(paid:, failed:, merchant_code: "MCH-TEST")
      paid.times   { create(:payment, provider: "telecel_cash", status: "paid",   merchant_code:, created_at: 10.minutes.ago) }
      failed.times { create(:payment, provider: "telecel_cash", status: "failed", merchant_code:, created_at: 10.minutes.ago) }
    end

    def airteltigo(paid:, failed:, merchant_code: "MCH-TEST")
      paid.times   { create(:payment, provider: "airteltigo",   status: "paid",   merchant_code:, created_at: 10.minutes.ago) }
      failed.times { create(:payment, provider: "airteltigo",   status: "failed", merchant_code:, created_at: 10.minutes.ago) }
    end

    def result_for(provider)
      NetworkHealthQuery.new(Payment.all).call.find { |n| n[:key] == provider }
    end

    # ── always returns 3 entries ───────────────────────────────────────────────

    test "always returns one entry per known provider even with no payments" do
      results = NetworkHealthQuery.new(Payment.all).call
      assert_equal 3, results.size
      assert_equal %w[mtn_momo telecel_cash airteltigo], results.map { |r| r[:key] }
    end

    # ── no_data when below minimum sample ─────────────────────────────────────

    test "returns no_data when fewer than MIN_SAMPLE terminal payments exist" do
      mtn(paid: 3, failed: 1)  # 4 total — below MIN_SAMPLE of 5

      r = result_for("mtn_momo")
      assert_equal :no_data, r[:status]
      assert_nil r[:rate]
    end

    test "returns no_data for a provider with zero recent payments" do
      # Only MTN has data; Telecel and AirtelTigo have nothing
      mtn(paid: 9, failed: 1)

      assert_equal :no_data, result_for("telecel_cash")[:status]
      assert_equal :no_data, result_for("airteltigo")[:status]
    end

    # ── healthy threshold (>= 90%) ─────────────────────────────────────────────

    test "healthy when 9 of 10 MTN payments succeeded (90%)" do
      mtn(paid: 9, failed: 1)  # exactly 90%

      r = result_for("mtn_momo")
      assert_equal :healthy, r[:status]
      assert_equal 90.0, r[:rate]
    end

    test "healthy when all 10 MTN payments succeeded (100%)" do
      mtn(paid: 10, failed: 0)

      r = result_for("mtn_momo")
      assert_equal :healthy, r[:status]
      assert_equal 100.0, r[:rate]
    end

    # ── degraded threshold (70–89.9%) ─────────────────────────────────────────

    test "degraded when 8 of 10 Telecel payments succeeded (80%)" do
      telecel(paid: 8, failed: 2)

      r = result_for("telecel_cash")
      assert_equal :degraded, r[:status]
      assert_equal 80.0, r[:rate]
    end

    test "degraded at exactly 70% (boundary)" do
      # 7 paid + 3 failed = 70%
      airteltigo(paid: 7, failed: 3)

      r = result_for("airteltigo")
      assert_equal :degraded, r[:status]
      assert_equal 70.0, r[:rate]
    end

    # ── disrupted threshold (< 70%) ───────────────────────────────────────────

    test "disrupted when 5 of 10 MTN payments succeeded (50%)" do
      mtn(paid: 5, failed: 5)

      r = result_for("mtn_momo")
      assert_equal :disrupted, r[:status]
      assert_equal 50.0, r[:rate]
    end

    test "disrupted when all payments failed" do
      mtn(paid: 0, failed: 6)

      r = result_for("mtn_momo")
      assert_equal :disrupted, r[:status]
      assert_equal 0.0, r[:rate]
    end

    # ── terminal status inclusion ──────────────────────────────────────────────

    test "cancelled and indeterminate payments count as failures" do
      # 6 paid + 2 cancelled + 2 indeterminate = 60% — disrupted
      6.times { create(:payment, provider: "mtn_momo", status: "paid",          created_at: 5.minutes.ago) }
      2.times { create(:payment, provider: "mtn_momo", status: "cancelled",     created_at: 5.minutes.ago) }
      2.times { create(:payment, provider: "mtn_momo", status: "indeterminate", created_at: 5.minutes.ago) }

      r = result_for("mtn_momo")
      assert_equal :disrupted, r[:status]
      assert_equal 60.0, r[:rate]
    end

    test "processing and created payments are excluded from calculation" do
      # 5 paid (healthy) + 10 processing (excluded) — should still be healthy
      mtn(paid: 5, failed: 0)
      5.times { create(:payment, provider: "mtn_momo", status: "processing", created_at: 5.minutes.ago) }
      5.times { create(:payment, provider: "mtn_momo", status: "created",    created_at: 5.minutes.ago) }

      r = result_for("mtn_momo")
      assert_equal :healthy, r[:status]
      assert_equal 100.0, r[:rate]
    end

    # ── time window ────────────────────────────────────────────────────────────

    test "excludes payments older than 30 minutes" do
      # 6 failed payments from 45 minutes ago — should not affect health
      6.times { create(:payment, provider: "mtn_momo", status: "failed", created_at: 45.minutes.ago) }
      # 5 paid payments in window
      5.times { create(:payment, provider: "mtn_momo", status: "paid",   created_at: 10.minutes.ago) }

      r = result_for("mtn_momo")
      # Only the 5 recent paid payments count → but MIN_SAMPLE is 5, so just meets threshold
      assert_equal :healthy, r[:status]
      assert_equal 100.0, r[:rate]
    end

    # ── relation scoping (merchant isolation) ─────────────────────────────────

    test "respects the scoped relation — merchant sees only their own network health" do
      # MCH-A has 10 paid MTN (healthy)
      mtn(paid: 10, failed: 0, merchant_code: "MCH-A")
      # MCH-B has 0 paid, 6 failed MTN (disrupted)
      mtn(paid: 0,  failed: 6, merchant_code: "MCH-B")

      # MCH-A's scoped query should see healthy
      mch_a_result = NetworkHealthQuery.new(Payment.where(merchant_code: "MCH-A")).call
      assert_equal :healthy, mch_a_result.find { |r| r[:key] == "mtn_momo" }[:status]

      # MCH-B's scoped query should see disrupted
      mch_b_result = NetworkHealthQuery.new(Payment.where(merchant_code: "MCH-B")).call
      assert_equal :disrupted, mch_b_result.find { |r| r[:key] == "mtn_momo" }[:status]
    end

    # ── simulator excluded ─────────────────────────────────────────────────────

    test "simulator provider is excluded from results" do
      10.times { create(:payment, provider: "simulator", status: "failed", created_at: 5.minutes.ago) }

      keys = NetworkHealthQuery.new(Payment.all).call.map { |r| r[:key] }
      assert_not_includes keys, "simulator"
      assert_equal 3, keys.size
    end

    # ── all three networks independent ────────────────────────────────────────

    test "each network is assessed independently with realistic mixed data" do
      # MTN: 95 paid, 5 failed — healthy
      mtn(paid: 19, failed: 1)  # 95%

      # Telecel: 16 paid, 4 failed — degraded (80%)
      telecel(paid: 16, failed: 4)

      # AirtelTigo: 3 paid — below MIN_SAMPLE, no_data
      airteltigo(paid: 3, failed: 0)

      results = NetworkHealthQuery.new(Payment.all).call
      by_key  = results.index_by { |r| r[:key] }

      assert_equal :healthy,   by_key["mtn_momo"][:status]
      assert_equal 95.0,       by_key["mtn_momo"][:rate]

      assert_equal :degraded,  by_key["telecel_cash"][:status]
      assert_equal 80.0,       by_key["telecel_cash"][:rate]

      assert_equal :no_data,   by_key["airteltigo"][:status]
      assert_nil               by_key["airteltigo"][:rate]
    end
  end
end
