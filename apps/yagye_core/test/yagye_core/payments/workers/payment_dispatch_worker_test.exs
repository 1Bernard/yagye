defmodule YagyeCore.Payments.Workers.PaymentDispatchWorkerTest do
  use YagyeCore.DataCase, async: true

  import Mox

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.MockProviderAdapter
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker

  setup :verify_on_exit!

  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    _credential = Fixtures.simulator_credential_fixture(provider)
    payment = Fixtures.payment_fixture(merchant)
    %{merchant: merchant, provider: provider, payment: payment}
  end

  test "transitions payment to succeeded and records attempt on success", %{payment: payment} do
    expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
      {:ok, %{provider_reference: "gw_test_ref", auth_code: "AUTH123"}}
    end)

    assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "succeeded"
    assert updated.version == 3

    attempt = Repo.get_by!(PaymentAttempt, payment_id: payment.id)
    assert attempt.state == "succeeded"
    assert attempt.provider_reference == "gw_test_ref"
    assert attempt.attempt_number == 1
  end

  test "transitions payment to failed on definite failure", %{payment: payment} do
    expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
      {:error,
       %{
         error_class: :definite_failure,
         response_code: "INSUFFICIENT_FUNDS",
         response_message: nil
       }}
    end)

    assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "failed"

    attempt = Repo.get_by!(PaymentAttempt, payment_id: payment.id)
    assert attempt.state == "failed"
    assert attempt.error_class == "definite_failure"
    assert attempt.response_code == "INSUFFICIENT_FUNDS"
  end

  test "transitions payment to indeterminate on timeout", %{payment: payment} do
    expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
      {:error, %{error_class: :indeterminate, response_code: "timeout", response_message: nil}}
    end)

    assert {:ok, _} = perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "indeterminate"

    attempt = Repo.get_by!(PaymentAttempt, payment_id: payment.id)
    assert attempt.state == "timed_out"
  end

  test "returns retryable error for Oban retry", %{payment: payment} do
    expect(MockProviderAdapter, :charge, fn _payment, _attempt, _credential ->
      {:error,
       %{error_class: :retryable_error, response_code: "GATEWAY_ERROR", response_message: nil}}
    end)

    assert {:error, :retryable_error} =
             perform_job(PaymentDispatchWorker, %{payment_id: payment.id}, [])

    updated = Repo.get!(Payment, payment.id)
    assert updated.state == "processing"
  end

  test "returns error for unknown payment" do
    assert {:error, :not_found} =
             perform_job(PaymentDispatchWorker, %{payment_id: Uniq.UUID.uuid7()}, [])
  end
end
