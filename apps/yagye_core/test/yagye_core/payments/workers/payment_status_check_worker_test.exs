defmodule YagyeCore.Payments.Workers.PaymentStatusCheckWorkerTest do
  use YagyeCore.DataCase, async: true

  import Mox

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.MockProviderAdapter
  alias YagyeCore.Payments
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Payments.Workers.PaymentStatusCheckWorker

  setup :verify_on_exit!

  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    _credential = Fixtures.simulator_credential_fixture(provider)

    payment =
      Fixtures.payment_fixture(merchant, %{
        method: "mobile_money",
        metadata: %{"network" => "MTN"}
      })

    # Advance to requires_action with a dispatched attempt
    {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
    {:ok, attempt} = Payments.create_attempt(payment, provider.id)

    {:ok, attempt} =
      attempt
      |> PaymentAttempt.result_changeset(%{
        state: "dispatched",
        provider_reference: "gw_test_ref"
      })
      |> Repo.update()

    {:ok, payment} = payment |> Payment.transition_changeset("requires_action") |> Repo.update()

    %{payment: payment, attempt: attempt, provider: provider}
  end

  test "transitions to succeeded when provider confirms authorised", %{
    payment: payment,
    attempt: attempt
  } do
    expect(MockProviderAdapter, :query_charge, fn _attempt, _credential ->
      {:ok, %{provider_reference: "gw_test_ref", auth_code: "AUTH999"}}
    end)

    args = %{
      "payment_id" => payment.id,
      "attempt_id" => attempt.id,
      "poll_number" => 1
    }

    assert {:ok, _payment} = perform_job(PaymentStatusCheckWorker, args)

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "succeeded"
  end

  test "transitions to failed on definite failure from provider", %{
    payment: payment,
    attempt: attempt
  } do
    expect(MockProviderAdapter, :query_charge, fn _attempt, _credential ->
      {:error,
       %{error_class: :definite_failure, response_code: "CARD_DECLINED", response_message: nil}}
    end)

    args = %{
      "payment_id" => payment.id,
      "attempt_id" => attempt.id,
      "poll_number" => 1
    }

    assert {:ok, _payment} = perform_job(PaymentStatusCheckWorker, args)

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "failed"
  end

  test "reschedules when provider is still pending and max not reached", %{
    payment: payment,
    attempt: attempt
  } do
    expect(MockProviderAdapter, :query_charge, fn _attempt, _credential ->
      {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
    end)

    args = %{
      "payment_id" => payment.id,
      "attempt_id" => attempt.id,
      "poll_number" => 1
    }

    assert :ok = perform_job(PaymentStatusCheckWorker, args)

    # Payment still in requires_action — a follow-up job was enqueued
    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "requires_action"

    assert_enqueued(worker: PaymentStatusCheckWorker, args: %{"poll_number" => 2})
  end

  test "stops polling when max attempts reached", %{payment: payment, attempt: attempt} do
    expect(MockProviderAdapter, :query_charge, fn _attempt, _credential ->
      {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
    end)

    args = %{
      "payment_id" => payment.id,
      "attempt_id" => attempt.id,
      "poll_number" => 12
    }

    assert :ok = perform_job(PaymentStatusCheckWorker, args)

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "requires_action"

    refute_enqueued(worker: PaymentStatusCheckWorker)
  end

  test "is a no-op when payment already resolved", %{payment: payment, attempt: attempt} do
    # Mark it succeeded first (e.g. webhook arrived before the poll)
    {:ok, _} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()

    args = %{
      "payment_id" => payment.id,
      "attempt_id" => attempt.id,
      "poll_number" => 1
    }

    # MockProviderAdapter.query_charge should NOT be called
    assert :ok = perform_job(PaymentStatusCheckWorker, args)

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "succeeded"
  end
end
