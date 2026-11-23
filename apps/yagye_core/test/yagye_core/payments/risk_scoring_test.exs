defmodule YagyeCore.Payments.RiskScoringTest do
  # async: false — each test overrides Application config (global state)
  use YagyeCore.DataCase, async: false

  alias YagyeCore.{Fixtures, Payments}

  @payment_attrs %{amount: 10_000, currency: "GHS", rail: "fiat_provider", method: "mobile_money"}

  setup do
    original_opts = Application.get_env(:yagye_core, :scoring_req_opts)
    original_scoring = Application.get_env(:yagye_core, :scoring)

    # Replace the global ScoringStub with a per-test Req.Test stub so active-mode
    # tests can control exact scorer responses. Shadow-mode tests also stub but the
    # stub runs in the test process; the fire-and-forget Task.start in shadow mode
    # runs in a separate process that cannot reach this stub — it fails silently,
    # which is intentional (shadow mode result is never used).
    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :scoring_http},
      retry: false
    )

    on_exit(fn ->
      Application.put_env(:yagye_core, :scoring_req_opts, original_opts)
      Application.put_env(:yagye_core, :scoring, original_scoring)
    end)

    %{merchant: Fixtures.merchant_fixture()}
  end

  defp stub_scorer(decision, score) do
    Req.Test.stub(:scoring_http, fn conn ->
      Req.Test.json(conn, %{"decision" => decision, "risk_score" => score, "reasons" => []})
    end)
  end

  defp enable_risk_ml! do
    cfg = Application.get_env(:yagye_core, :scoring)
    Application.put_env(:yagye_core, :scoring, Keyword.put(cfg, :risk_ml_enabled, true))
  end

  # ── Shadow mode (risk_ml_enabled: false) ─────────────────────────────────────

  describe "shadow mode — scorer result never influences payment creation" do
    test "payment is created and risk fields are not stored", %{merchant: merchant} do
      # Stub returns "block" — in active mode this would reject the payment.
      # In shadow mode the decision is ignored; the scorer fires async (Task.start)
      # and the result is discarded.
      stub_scorer("block", 0.99)

      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)
      assert payment.state == "created"
      assert is_nil(payment.risk_decision)
      assert is_nil(payment.risk_score)
    end
  end

  # ── Active mode (risk_ml_enabled: true) ──────────────────────────────────────

  describe "active mode — scorer decision is enforced synchronously" do
    setup do
      enable_risk_ml!()
      :ok
    end

    test "payment is rejected when scorer returns 'block'", %{merchant: merchant} do
      stub_scorer("block", 0.97)

      assert {:error, :payment_blocked_by_risk} =
               Payments.create_payment(merchant.id, @payment_attrs)
    end

    test "payment is created with risk fields when scorer returns 'review'", %{merchant: merchant} do
      stub_scorer("review", 0.76)

      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)
      assert payment.state == "created"
      assert payment.risk_decision == "review"
      assert_in_delta Decimal.to_float(payment.risk_score), 0.76, 0.001
    end

    test "payment is created with risk fields when scorer returns 'allow'", %{merchant: merchant} do
      stub_scorer("allow", 0.12)

      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)
      assert payment.state == "created"
      assert payment.risk_decision == "allow"
      assert_in_delta Decimal.to_float(payment.risk_score), 0.12, 0.001
    end

    test "payment is created (fail-open) when scoring service is unavailable", %{
      merchant: merchant
    } do
      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      # Scoring unavailability must never block payments — the PSP must keep
      # processing even when the ML service is down.
      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)
      assert payment.state == "created"
      assert is_nil(payment.risk_decision)
      assert is_nil(payment.risk_score)
    end

    test "payment is created (fail-open) when scoring service returns 500", %{merchant: merchant} do
      Req.Test.stub(:scoring_http, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)
      assert payment.state == "created"
      assert is_nil(payment.risk_decision)
    end
  end
end
