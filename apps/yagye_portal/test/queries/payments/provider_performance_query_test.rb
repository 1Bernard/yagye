# frozen_string_literal: true

require "test_helper"

module Payments
  class ProviderPerformanceQueryTest < ActiveSupport::TestCase
    # ── helpers ────────────────────────────────────────────────────────────────

    # Unique merchant code per test file keeps pre-existing data from leaking in.
    MCH = "MCH-PROV-PERF-TEST"

    def payment(provider:, status:, amount: 5_000, fee_amount: nil, merchant_code: MCH,
                currency: "GHS", created_at: 10.minutes.ago, paid_at: nil)
      paid_at_val = status == "paid" ? (paid_at || (created_at + 8.seconds)) : nil
      create(:payment,
             provider:      provider,
             status:        status,
             amount:        amount,
             fee_amount:    fee_amount,
             currency:      currency,
             merchant_code: merchant_code,
             created_at:    created_at,
             paid_at:       paid_at_val,
             mode:          "live")
    end

    def from = 30.days.ago
    def to   = Time.current

    def run_query(merchant_code: MCH)
      ProviderPerformanceQuery.new(Payment.where(merchant_code: merchant_code)).call(from: from, to: to)
    end

    def result_for(provider)
      run_query.find { |r| r.provider == provider }
    end

    # ── basic aggregation ──────────────────────────────────────────────────────

    test "returns one row per provider" do
      payment(provider: "mtn_momo", status: "paid")
      payment(provider: "mtn_momo", status: "failed")
      payment(provider: "stripe",   status: "paid")

      rows = run_query
      providers = rows.map(&:provider).sort
      assert_equal %w[mtn_momo stripe], providers
    end

    test "counts terminal statuses correctly" do
      payment(provider: "mtn_momo", status: "paid")
      payment(provider: "mtn_momo", status: "failed")
      payment(provider: "mtn_momo", status: "cancelled")
      payment(provider: "mtn_momo", status: "indeterminate")

      r = result_for("mtn_momo")
      assert_equal 4, r.terminal_count
      assert_equal 1, r.succeeded_count
      assert_equal 3, r.failed_count
    end

    test "calculates success_rate correctly" do
      8.times { payment(provider: "stripe", status: "paid") }
      2.times { payment(provider: "stripe", status: "failed") }

      r = result_for("stripe")
      assert_equal 10, r.terminal_count
      assert_equal 8,  r.succeeded_count
      assert_equal 80.0, r.success_rate
    end

    test "success_rate is 100.0 when all payments succeed" do
      5.times { payment(provider: "paystack", status: "paid") }

      r = result_for("paystack")
      assert_equal 100.0, r.success_rate
    end

    test "success_rate is 0.0 when all payments fail" do
      3.times { payment(provider: "mtn_momo", status: "failed") }

      r = result_for("mtn_momo")
      assert_equal 0.0, r.success_rate
    end

    # ── volume and fees ────────────────────────────────────────────────────────

    test "sums gross_volume only for paid payments" do
      payment(provider: "stripe", status: "paid",   amount: 20_000)
      payment(provider: "stripe", status: "failed", amount: 10_000)

      r = result_for("stripe")
      assert_equal 20_000, r.gross_volume
    end

    test "sums total_fees only for paid payments" do
      payment(provider: "mtn_momo", status: "paid",   amount: 10_000, fee_amount: 300)
      payment(provider: "mtn_momo", status: "paid",   amount: 10_000, fee_amount: 400)
      payment(provider: "mtn_momo", status: "failed", amount: 10_000, fee_amount: nil)

      r = result_for("mtn_momo")
      assert_equal 700, r.total_fees
    end

    test "total_fees is 0 when no fee_amount on paid payments" do
      payment(provider: "stripe", status: "paid", amount: 10_000, fee_amount: nil)

      r = result_for("stripe")
      assert_equal 0, r.total_fees
    end

    # ── exclusions ─────────────────────────────────────────────────────────────

    test "excludes simulator provider" do
      payment(provider: "simulator", status: "paid")
      payment(provider: "mtn_momo",  status: "paid")

      providers = run_query.map(&:provider)
      assert_not_includes providers, "simulator"
      assert_includes     providers, "mtn_momo"
    end

    test "excludes non-terminal statuses from counts" do
      payment(provider: "stripe", status: "paid")
      payment(provider: "stripe", status: "processing")
      payment(provider: "stripe", status: "created")
      payment(provider: "stripe", status: "requires_action")

      r = result_for("stripe")
      assert_equal 1, r.terminal_count
      assert_equal 1, r.succeeded_count
      assert_equal 100.0, r.success_rate
    end

    test "excludes payments outside the date range" do
      payment(provider: "mtn_momo", status: "paid", created_at: 60.days.ago)

      rows = ProviderPerformanceQuery.new(Payment.where(merchant_code: MCH))
                                     .call(from: 30.days.ago, to: Time.current)
      assert_empty rows
    end

    # ── currency filtering ─────────────────────────────────────────────────────

    test "filters by currency" do
      payment(provider: "stripe",   status: "paid", currency: "USD")
      payment(provider: "mtn_momo", status: "paid", currency: "GHS")

      scope = Payment.where(merchant_code: MCH)
      ghs_rows = ProviderPerformanceQuery.new(scope).call(from: from, to: to, currency: "GHS")
      usd_rows = ProviderPerformanceQuery.new(scope).call(from: from, to: to, currency: "USD")

      assert_equal %w[mtn_momo], ghs_rows.map(&:provider)
      assert_equal %w[stripe],   usd_rows.map(&:provider)
    end

    # ── relation scoping (merchant isolation) ─────────────────────────────────

    test "respects the scoped relation — merchant sees only their own data" do
      5.times { payment(provider: "stripe",   status: "paid",   merchant_code: "MCH-PERF-A") }
      2.times { payment(provider: "mtn_momo", status: "failed", merchant_code: "MCH-PERF-B") }

      mch_a_rows = ProviderPerformanceQuery.new(Payment.where(merchant_code: "MCH-PERF-A")).call(from: from, to: to)
      assert_equal 1, mch_a_rows.size
      assert_equal "stripe", mch_a_rows.first.provider
      assert_equal 100.0,    mch_a_rows.first.success_rate

      mch_b_rows = ProviderPerformanceQuery.new(Payment.where(merchant_code: "MCH-PERF-B")).call(from: from, to: to)
      assert_equal 1, mch_b_rows.size
      assert_equal "mtn_momo", mch_b_rows.first.provider
      assert_equal 0.0,        mch_b_rows.first.success_rate
    end

    # ── ordered by gross volume desc ──────────────────────────────────────────

    test "orders rows by gross_volume descending" do
      payment(provider: "mtn_momo", status: "paid", amount: 5_000)
      payment(provider: "stripe",   status: "paid", amount: 50_000)
      payment(provider: "paystack", status: "paid", amount: 25_000)

      providers = run_query.map(&:provider)
      assert_equal %w[stripe paystack mtn_momo], providers
    end

    test "returns empty array when no terminal payments exist" do
      rows = run_query
      assert_equal [], rows
    end
  end
end
