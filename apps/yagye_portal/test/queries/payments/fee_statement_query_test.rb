# frozen_string_literal: true

require "test_helper"

module Payments
  class FeeStatementQueryTest < ActiveSupport::TestCase
    # ── helpers ────────────────────────────────────────────────────────────────

    # Unique merchant code per test file keeps pre-existing data from leaking in.
    MCH = "MCH-FEE-STMT-TEST"

    def paid(provider:, amount:, fee_amount:, merchant_code: MCH, currency: "GHS", paid_at: 5.days.ago)
      create(:payment,
             provider:      provider,
             status:        "paid",
             amount:        amount,
             fee_amount:    fee_amount,
             net_amount:    amount - fee_amount,
             currency:      currency,
             merchant_code: merchant_code,
             paid_at:       paid_at,
             mode:          "live")
    end

    def from = 30.days.ago
    def to   = Time.current

    def run_query(merchant_code: MCH)
      FeeStatementQuery.new(Payment.where(merchant_code: merchant_code)).call(from: from, to: to)
    end

    # ── basic aggregation ──────────────────────────────────────────────────────

    test "returns one row per provider sorted by total_fees desc" do
      paid(provider: "mtn_momo",   amount: 10_000, fee_amount: 200)
      paid(provider: "mtn_momo",   amount: 10_000, fee_amount: 200)
      paid(provider: "stripe",     amount: 50_000, fee_amount: 1_500)

      rows = run_query
      assert_equal 2, rows.size
      assert_equal "stripe",   rows.first.provider
      assert_equal "mtn_momo", rows.last.provider
    end

    test "sums fee_amount correctly per provider" do
      paid(provider: "mtn_momo", amount: 10_000, fee_amount: 300)
      paid(provider: "mtn_momo", amount: 20_000, fee_amount: 500)

      row = run_query.find { |r| r.provider == "mtn_momo" }
      assert_equal 800, row.total_fees
      assert_equal 2,   row.tx_count
    end

    test "sums gross_volume (amount) per provider" do
      paid(provider: "stripe", amount: 25_000, fee_amount: 400)
      paid(provider: "stripe", amount: 15_000, fee_amount: 300)

      row = run_query.find { |r| r.provider == "stripe" }
      assert_equal 40_000, row.gross_volume
    end

    test "net_volume equals gross minus fees when net_amount is set" do
      paid(provider: "paystack", amount: 10_000, fee_amount: 200)

      row = run_query.find { |r| r.provider == "paystack" }
      assert_equal 9_800, row.net_volume
    end

    # ── exclusions ─────────────────────────────────────────────────────────────

    test "excludes payments with no fee_amount" do
      create(:payment, provider: "mtn_momo", status: "paid", amount: 10_000,
             fee_amount: nil, merchant_code: "MCH-TEST", paid_at: 5.days.ago, mode: "live")
      paid(provider: "stripe", amount: 20_000, fee_amount: 400)

      rows = run_query
      assert_equal 1, rows.size
      assert_equal "stripe", rows.first.provider
    end

    test "excludes payments with fee_amount zero" do
      create(:payment, provider: "mtn_momo", status: "paid", amount: 10_000,
             fee_amount: 0, merchant_code: "MCH-TEST", paid_at: 5.days.ago, mode: "live")

      rows = run_query
      assert_empty rows
    end

    test "excludes non-paid payments" do
      create(:payment, provider: "stripe", status: "failed", amount: 10_000,
             fee_amount: 300, merchant_code: "MCH-TEST", created_at: 5.days.ago, mode: "live")

      rows = run_query
      assert_empty rows
    end

    test "excludes payments outside the date range" do
      paid(provider: "mtn_momo", amount: 10_000, fee_amount: 200,
           paid_at: 60.days.ago)

      rows = FeeStatementQuery.new(Payment.where(merchant_code: MCH))
                              .call(from: 30.days.ago, to: Time.current)
      assert_empty rows
    end

    # ── date range boundary ────────────────────────────────────────────────────

    test "includes payments at the from boundary" do
      paid(provider: "stripe", amount: 10_000, fee_amount: 400,
           paid_at: 30.days.ago + 1.second)

      rows = FeeStatementQuery.new(Payment.where(merchant_code: MCH))
                              .call(from: 30.days.ago, to: Time.current)
      assert_equal 1, rows.size
    end

    # ── currency filtering ─────────────────────────────────────────────────────

    test "filters by currency" do
      paid(provider: "stripe",   amount: 50_000, fee_amount: 1_500, currency: "USD")
      paid(provider: "mtn_momo", amount: 10_000, fee_amount: 200,   currency: "GHS")

      scope = Payment.where(merchant_code: MCH)
      ghs_rows = FeeStatementQuery.new(scope).call(from: from, to: to, currency: "GHS")
      usd_rows = FeeStatementQuery.new(scope).call(from: from, to: to, currency: "USD")

      assert_equal 1, ghs_rows.size
      assert_equal "mtn_momo", ghs_rows.first.provider

      assert_equal 1, usd_rows.size
      assert_equal "stripe", usd_rows.first.provider
    end

    # ── relation scoping (merchant isolation) ─────────────────────────────────

    test "respects the scoped relation — merchant sees only their own fees" do
      paid(provider: "stripe",   amount: 50_000, fee_amount: 1_000, merchant_code: "MCH-FEE-A")
      paid(provider: "mtn_momo", amount: 10_000, fee_amount: 200,   merchant_code: "MCH-FEE-B")

      mch_a_rows = FeeStatementQuery.new(Payment.where(merchant_code: "MCH-FEE-A")).call(from: from, to: to)
      assert_equal 1, mch_a_rows.size
      assert_equal "stripe", mch_a_rows.first.provider

      mch_b_rows = FeeStatementQuery.new(Payment.where(merchant_code: "MCH-FEE-B")).call(from: from, to: to)
      assert_equal 1, mch_b_rows.size
      assert_equal "mtn_momo", mch_b_rows.first.provider
    end

    # ── result struct fields ───────────────────────────────────────────────────

    test "result carries currency from the data" do
      paid(provider: "mtn_momo", amount: 10_000, fee_amount: 200, currency: "GHS")

      row = run_query.first
      assert_equal "GHS", row.currency
    end

    test "returns empty array when no matching payments exist" do
      rows = run_query
      assert_equal [], rows
    end
  end
end
