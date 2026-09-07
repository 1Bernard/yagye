defmodule YagyeCore.Payments.Workers.PaymentTimeoutWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.Payments
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Payments.Workers.PaymentTimeoutWorker

  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    _credential = Fixtures.simulator_credential_fixture(provider)
    payment = Fixtures.payment_fixture(merchant, %{method: "mobile_money"})

    {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
    {:ok, attempt} = Payments.create_attempt(payment, provider.id)

    {:ok, attempt} =
      attempt
      |> PaymentAttempt.result_changeset(%{state: "dispatched", provider_reference: "gw_ref"})
      |> Repo.update()

    {:ok, payment} = payment |> Payment.transition_changeset("requires_action") |> Repo.update()

    %{payment: payment, attempt: attempt}
  end

  test "marks payment failed and attempt abandoned when still requires_action", %{
    payment: payment,
    attempt: attempt
  } do
    args = %{"payment_id" => payment.id, "attempt_id" => attempt.id}

    assert {:ok, _payment} = perform_job(PaymentTimeoutWorker, args)

    updated_payment = Repo.get!(Payment, payment.id)
    assert updated_payment.state == "failed"

    updated_attempt = Repo.get!(PaymentAttempt, attempt.id)
    assert updated_attempt.state == "abandoned"
    assert updated_attempt.response_code == "prompt_timeout"
  end

  test "is a no-op when payment already succeeded (webhook beat the timeout)", %{
    payment: payment,
    attempt: attempt
  } do
    # Simulate webhook arriving and resolving the payment before timeout fires
    {:ok, _} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()

    args = %{"payment_id" => payment.id, "attempt_id" => attempt.id}

    assert :ok = perform_job(PaymentTimeoutWorker, args)

    # Should still be succeeded — timeout was a no-op
    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "succeeded"
  end

  test "is a no-op when payment already failed (e.g. double-fired)", %{
    payment: payment,
    attempt: attempt
  } do
    {:ok, _} = payment |> Payment.transition_changeset("failed") |> Repo.update()

    args = %{"payment_id" => payment.id, "attempt_id" => attempt.id}

    assert :ok = perform_job(PaymentTimeoutWorker, args)

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "failed"
  end
end
