defmodule YagyeCore.Payments.Workers.PaymentSimulatorWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Payments, Repo}
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Workers.PaymentSimulatorWorker

  test "transitions payment to succeeded" do
    merchant = Fixtures.merchant_fixture()
    payment = Fixtures.payment_fixture(merchant)
    {:ok, _} = Payments.dispatch_payment(payment.id)

    assert {:ok, _} = perform_job(PaymentSimulatorWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "succeeded"
    assert updated.version == 3
  end

  test "returns error for unknown payment" do
    assert {:error, :not_found} =
             perform_job(PaymentSimulatorWorker, %{payment_id: Uniq.UUID.uuid7()}, [])
  end
end
