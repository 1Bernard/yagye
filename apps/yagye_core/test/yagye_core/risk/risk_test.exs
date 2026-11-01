defmodule YagyeCore.RiskTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Risk
  alias YagyeCore.Risk.Schemas.RiskLabel

  # Insert a payment row directly — bypasses create_payment scoring path.
  defp insert_payment(attrs \\ []) do
    merchant = insert_merchant()

    base = [
      public_id: "pay_" <> Uniq.UUID.uuid7(),
      merchant_id: merchant.id,
      mode: "simulation",
      amount: 10_000,
      currency: "GHS",
      rail: "fiat_provider",
      method: "mobile_money",
      state: "succeeded",
      version: 0,
      metadata: %{}
    ]

    Repo.insert!(struct(Payment, Keyword.merge(base, attrs)))
  end

  defp insert_merchant do
    alias YagyeCore.Merchants.Schemas.Merchant

    Repo.insert!(%Merchant{
      public_id: "mch_" <> Uniq.UUID.uuid7(),
      legal_name: "Test Merchant #{System.unique_integer([:positive])}",
      trading_name: "Test Co",
      country: "GH",
      default_currency: "GHS",
      status: "active",
      metadata: %{}
    })
  end

  defp insert_risk_label(payment, attrs) do
    base = [
      payment_id: payment.id,
      label: "suspicious",
      labelled_by: "analyst@yagye.com"
    ]

    %RiskLabel{}
    |> RiskLabel.changeset(Map.new(Keyword.merge(base, attrs)))
    |> Repo.insert!()
  end

  # ── flag_payment/2 ────────────────────────────────────────────────────────────

  describe "flag_payment/2" do
    test "flags an unflagged payment" do
      payment = insert_payment()

      assert {:ok, updated} = Risk.flag_payment(payment.id, "analyst@yagye.com")
      assert updated.risk_flagged_at != nil
      assert updated.risk_decision == "review"
    end

    test "preserves block decision when flagging a blocked payment" do
      payment = insert_payment(risk_decision: "block")

      assert {:ok, updated} = Risk.flag_payment(payment.id, "analyst@yagye.com")
      assert updated.risk_decision == "block"
      assert updated.risk_flagged_at != nil
    end

    test "returns :already_flagged for an already-flagged payment" do
      payment = insert_payment(risk_flagged_at: DateTime.utc_now())

      assert {:error, :already_flagged} = Risk.flag_payment(payment.id, "analyst@yagye.com")
    end

    test "returns :not_found for unknown payment_id" do
      assert {:error, :not_found} = Risk.flag_payment(Ecto.UUID.generate(), "analyst@yagye.com")
    end
  end

  # ── dispose_case/4 ────────────────────────────────────────────────────────────

  describe "dispose_case/4" do
    test "creates a risk label for a flagged payment" do
      payment = insert_payment(risk_flagged_at: DateTime.utc_now())

      assert {:ok, label} =
               Risk.dispose_case(
                 payment.id,
                 "false_positive",
                 "reviewer@yagye.com",
                 "Legitimate transfer"
               )

      assert label.label == "false_positive"
      assert label.labelled_by == "reviewer@yagye.com"
      assert label.note == "Legitimate transfer"
      assert label.payment_id == payment.id
    end

    test "returns :not_flagged for an unflagged payment" do
      payment = insert_payment()

      assert {:error, :not_flagged} =
               Risk.dispose_case(payment.id, "false_positive", "reviewer@yagye.com")
    end

    test "returns :not_found for unknown payment" do
      assert {:error, :not_found} =
               Risk.dispose_case(Ecto.UUID.generate(), "confirmed_fraud", "reviewer@yagye.com")
    end

    test "changeset rejects invalid labels" do
      payment = insert_payment(risk_flagged_at: DateTime.utc_now())

      assert {:error, changeset} =
               Risk.dispose_case(payment.id, "not_a_real_label", "reviewer@yagye.com")

      assert %{label: _} = errors_on(changeset)
    end
  end

  # ── list_flagged/1 ────────────────────────────────────────────────────────────

  describe "list_flagged/1" do
    test "returns only payments with risk_flagged_at set" do
      flagged = insert_payment(risk_flagged_at: DateTime.utc_now(), risk_decision: "review")
      _unflagged = insert_payment()

      assert {:ok, page} = Risk.list_flagged()
      ids = Enum.map(page.data, & &1.id)
      assert flagged.id in ids
      refute Enum.any?(page.data, &is_nil(&1.risk_flagged_at))
    end

    test "filters by decision" do
      _review = insert_payment(risk_flagged_at: DateTime.utc_now(), risk_decision: "review")
      _blocked = insert_payment(risk_flagged_at: DateTime.utc_now(), risk_decision: "block")

      assert {:ok, page} = Risk.list_flagged(decision: "block")
      assert Enum.all?(page.data, &(&1.risk_decision == "block"))
    end
  end

  # ── get_case/1 ────────────────────────────────────────────────────────────────

  describe "get_case/1" do
    test "returns payment and its labels" do
      payment = insert_payment(risk_flagged_at: DateTime.utc_now())
      insert_risk_label(payment, label: "suspicious")

      assert {:ok, {fetched, labels}} = Risk.get_case(payment.id)
      assert fetched.id == payment.id
      assert length(labels) == 1
      assert hd(labels).label == "suspicious"
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Risk.get_case(Ecto.UUID.generate())
    end
  end
end
