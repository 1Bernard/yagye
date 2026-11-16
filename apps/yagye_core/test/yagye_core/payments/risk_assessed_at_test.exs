defmodule YagyeCore.Payments.RiskAssessedAtTest do
  # async: false — overrides Application env for scoring config
  use YagyeCore.DataCase, async: false

  alias YagyeCore.{Fixtures, Payments}

  @payment_attrs %{
    amount: 10_000,
    currency: "GHS",
    rail: "fiat_provider",
    method: "mobile_money"
  }

  setup do
    original_scoring = Application.get_env(:yagye_core, :scoring)
    original_req_opts = Application.get_env(:yagye_core, :scoring_req_opts)

    on_exit(fn ->
      Application.put_env(:yagye_core, :scoring, original_scoring)
      Application.put_env(:yagye_core, :scoring_req_opts, original_req_opts)
    end)

    merchant = Fixtures.merchant_fixture()
    %{merchant: merchant}
  end

  defp enable_inline_scoring do
    existing = Application.get_env(:yagye_core, :scoring, [])

    Application.put_env(
      :yagye_core,
      :scoring,
      Keyword.merge(existing, risk_ml_enabled: true, routing_ml_rollout_percent: 0)
    )

    Application.put_env(:yagye_core, :scoring_req_opts,
      plug: {Req.Test, :scoring_http},
      retry: false
    )
  end

  describe "risk_assessed_at — inline scoring (risk_ml_enabled: true)" do
    test "is set when scoring returns allow", %{merchant: merchant} do
      enable_inline_scoring()

      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{"decision" => "allow", "score" => 0.1, "reasons" => []})
      end)

      {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)

      refute is_nil(payment.risk_assessed_at)
      assert payment.risk_decision == "allow"
      assert Decimal.compare(payment.risk_score, Decimal.new("0.1")) == :eq
    end

    test "is set when scoring returns review", %{merchant: merchant} do
      enable_inline_scoring()

      Req.Test.stub(:scoring_http, fn conn ->
        Req.Test.json(conn, %{"decision" => "review", "score" => 0.65, "reasons" => []})
      end)

      {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)

      refute is_nil(payment.risk_assessed_at)
      assert payment.risk_decision == "review"
    end

    test "is nil when scoring service is unavailable", %{merchant: merchant} do
      enable_inline_scoring()

      Req.Test.stub(:scoring_http, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)

      assert is_nil(payment.risk_assessed_at)
      assert is_nil(payment.risk_decision)
      assert is_nil(payment.risk_score)
    end
  end

  describe "risk_assessed_at — shadow mode (risk_ml_enabled: false)" do
    test "is nil because scoring result is not applied to the payment", %{merchant: merchant} do
      # Default test config has risk_ml_enabled: false (shadow mode).
      # score_risk_inline fires Task.start and returns %{} — no risk fields written.
      {:ok, {payment, _event}} = Payments.create_payment(merchant.id, @payment_attrs)

      assert is_nil(payment.risk_assessed_at)
      assert is_nil(payment.risk_decision)
      assert is_nil(payment.risk_score)
    end
  end
end
