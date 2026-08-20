defmodule YagyeCore.Payments.Workers.PaymentDispatchWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Workers.{PaymentDispatchWorker, PaymentSimulatorWorker}

  test "transitions payment to processing" do
    merchant = Fixtures.merchant_fixture()
    payment = Fixtures.payment_fixture(merchant)

    assert :ok = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "processing"
    assert updated.version == 1
  end

  test "enqueues simulator for simulation mode payment" do
    merchant = Fixtures.merchant_fixture()
    payment = Fixtures.payment_fixture(merchant)

    assert :ok = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    assert_enqueued(worker: PaymentSimulatorWorker, args: %{payment_id: payment.id})
  end

  test "returns error for unknown payment" do
    assert {:error, :not_found} =
             perform_job(PaymentDispatchWorker, %{payment_id: Uniq.UUID.uuid7()}, [])
  end
end
