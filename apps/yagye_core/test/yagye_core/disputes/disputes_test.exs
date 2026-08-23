defmodule YagyeCore.Disputes.DisputesTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Disputes
  alias YagyeCore.Fixtures

  setup do
    merchant = Fixtures.approved_merchant_fixture()
    {:ok, merchant: merchant}
  end

  describe "create_dispute/2" do
    test "opens dispute and transitions payment to disputed", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      {:ok, {dispute, payment}} =
        Disputes.create_dispute(payment, %{
          network: "MTN",
          reason: "fraud",
          amount: payment.amount
        })

      assert dispute.stage == "opened"
      assert dispute.payment_id == payment.id
      assert dispute.merchant_id == merchant.id
      assert String.starts_with?(dispute.public_id, "dsp_")
      assert payment.state == "disputed"
    end

    test "rejects dispute on non-succeeded payment", %{merchant: merchant} do
      payment = Fixtures.payment_fixture(merchant)

      assert {:error, {:not_disputable, "created"}} =
               Disputes.create_dispute(payment, %{
                 network: "VISA",
                 reason: "fraud",
                 amount: 5_000
               })
    end
  end

  describe "resolve_dispute/2" do
    test "won outcome transitions payment back to succeeded", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)
      {:ok, {dispute, _}} = Disputes.create_dispute(payment, dispute_attrs(payment))

      {:ok, {dispute, payment}} = Disputes.resolve_dispute(dispute, :won)

      assert dispute.stage == "resolved"
      assert dispute.outcome == "won"
      assert payment.state == "succeeded"
    end

    test "lost outcome transitions payment to chargebacked", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)
      {:ok, {dispute, _}} = Disputes.create_dispute(payment, dispute_attrs(payment))

      {:ok, {dispute, payment}} = Disputes.resolve_dispute(dispute, :lost)

      assert dispute.outcome == "lost"
      assert payment.state == "chargebacked"
    end

    test "cannot resolve an already-resolved dispute", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)
      {:ok, {dispute, _}} = Disputes.create_dispute(payment, dispute_attrs(payment))
      {:ok, _} = Disputes.resolve_dispute(dispute, :won)

      # Fetch the now-resolved dispute
      {:ok, resolved} = Disputes.get_dispute(dispute.public_id)
      assert {:error, :already_resolved} = Disputes.resolve_dispute(resolved, :lost)
    end
  end

  describe "create_refund/2 — no dispute" do
    test "refunds a succeeded payment and transitions to refunded", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      {:ok, {refund, payment}} =
        Disputes.create_refund(payment, %{amount: payment.amount, reason: "customer_request"})

      assert refund.state == "succeeded"
      assert refund.amount == payment.amount
      assert String.starts_with?(refund.public_id, "ref_")
      assert refund.dispute_id == nil
      assert payment.state == "refunded"
    end

    test "partial refund is accepted", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      {:ok, {refund, payment}} =
        Disputes.create_refund(payment, %{amount: 5_000, reason: "duplicate"})

      assert refund.amount == 5_000
      assert payment.state == "refunded"
    end

    test "rejects refund amount exceeding original", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant, %{amount: 10_000})

      assert {:error, :amount_exceeds_original} =
               Disputes.create_refund(payment, %{amount: 10_001, reason: "duplicate"})
    end

    test "rejects refund on non-refundable state", %{merchant: merchant} do
      payment = Fixtures.payment_fixture(merchant)

      assert {:error, {:not_refundable, "created"}} =
               Disputes.create_refund(payment, %{amount: 5_000, reason: "duplicate"})
    end
  end

  describe "create_refund/2 — retracts open dispute" do
    test "refund on disputed payment retracts the dispute", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)
      {:ok, {dispute, payment}} = Disputes.create_dispute(payment, dispute_attrs(payment))

      {:ok, {refund, payment}} =
        Disputes.create_refund(payment, %{amount: payment.amount})

      assert payment.state == "refunded"
      assert refund.dispute_id == dispute.id
      assert refund.reason == "dispute_retracted"

      {:ok, resolved_dispute} = Disputes.get_dispute(dispute.public_id)
      assert resolved_dispute.stage == "resolved"
      assert resolved_dispute.outcome == "retracted"
    end
  end

  describe "get_dispute/1 and get_refund/1" do
    test "returns dispute by public_id", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)
      {:ok, {dispute, _}} = Disputes.create_dispute(payment, dispute_attrs(payment))

      assert {:ok, found} = Disputes.get_dispute(dispute.public_id)
      assert found.id == dispute.id
    end

    test "returns not_found for unknown public_id" do
      assert {:error, :not_found} = Disputes.get_dispute("dsp_doesnotexist")
    end

    test "returns refund by public_id", %{merchant: merchant} do
      payment = Fixtures.succeeded_payment_fixture(merchant)

      {:ok, {refund, _}} =
        Disputes.create_refund(payment, %{amount: payment.amount, reason: "fraudulent"})

      assert {:ok, found} = Disputes.get_refund(refund.public_id)
      assert found.id == refund.id
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp dispute_attrs(payment) do
    %{network: "MTN", reason: "fraud", amount: payment.amount}
  end
end
