defmodule YagyeCore.Payments.MomoRecoveryTest do
  @moduledoc """
  Tests for the MoMo requires_action recovery path:

  1. Atomic scheduling — `handle_pending_auth` enqueues recovery workers inside the transaction.
  2. Scanner backstop — `StuckPaymentScannerWorker` picks up orphaned requires_action payments.
  """

  use YagyeCore.DataCase, async: true

  import Ecto.Query

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.Payments
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}

  alias YagyeCore.Payments.Workers.{
    PaymentStatusCheckWorker,
    PaymentTimeoutWorker,
    StuckPaymentScannerWorker
  }

  # ── Gap 1: atomic scheduling ──────────────────────────────────────────────────

  describe "handle_pending_auth/3 atomically schedules recovery workers" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _credential = Fixtures.simulator_credential_fixture(provider)

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN"}
        })

      {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)

      %{payment: payment, attempt: attempt}
    end

    test "enqueues PaymentStatusCheckWorker inside the same transaction", %{
      payment: payment,
      attempt: attempt
    } do
      {:ok, _} = Payments.handle_pending_auth(payment, attempt, %{provider_reference: "gw_ref"})

      assert_enqueued(
        worker: PaymentStatusCheckWorker,
        args: %{"payment_id" => payment.id, "attempt_id" => attempt.id, "poll_number" => 1}
      )
    end

    test "enqueues PaymentTimeoutWorker inside the same transaction", %{
      payment: payment,
      attempt: attempt
    } do
      {:ok, _} = Payments.handle_pending_auth(payment, attempt, %{provider_reference: "gw_ref"})

      assert_enqueued(
        worker: PaymentTimeoutWorker,
        args: %{"payment_id" => payment.id, "attempt_id" => attempt.id}
      )
    end

    test "transitions payment to requires_action", %{payment: payment, attempt: attempt} do
      {:ok, updated} =
        Payments.handle_pending_auth(payment, attempt, %{provider_reference: "gw_ref"})

      assert updated.state == "requires_action"
    end
  end

  # ── Gap 2: scanner backstop for requires_action ───────────────────────────────

  describe "StuckPaymentScannerWorker.perform/1 — requires_action sweep" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _credential = Fixtures.simulator_credential_fixture(provider)

      payment =
        Fixtures.payment_fixture(merchant, %{
          method: "mobile_money",
          metadata: %{"network" => "MTN"}
        })

      {:ok, payment} = payment |> Payment.transition_changeset("processing") |> Repo.update()
      {:ok, attempt} = Payments.create_attempt(payment, provider.id)

      {:ok, attempt} =
        attempt
        |> PaymentAttempt.result_changeset(%{state: "dispatched", provider_reference: "gw_ref"})
        |> Repo.update()

      {:ok, payment} = payment |> Payment.transition_changeset("requires_action") |> Repo.update()

      %{payment: payment, attempt: attempt}
    end

    test "re-enqueues PaymentStatusCheckWorker for old requires_action payment", %{
      payment: payment,
      attempt: attempt
    } do
      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -8 * 60, :second)]
      )

      assert :ok = perform_job(StuckPaymentScannerWorker, %{})

      assert_enqueued(
        worker: PaymentStatusCheckWorker,
        args: %{"payment_id" => payment.id, "attempt_id" => attempt.id, "poll_number" => 1}
      )
    end

    test "ignores requires_action payment younger than 7-minute threshold", %{payment: payment} do
      jobs_before = count_status_check_jobs(payment.id)

      assert :ok = perform_job(StuckPaymentScannerWorker, %{})

      assert count_status_check_jobs(payment.id) == jobs_before
    end

    test "ignores succeeded payment older than threshold", %{payment: payment} do
      {:ok, payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()

      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -10 * 60, :second)]
      )

      jobs_before = count_status_check_jobs(payment.id)

      assert :ok = perform_job(StuckPaymentScannerWorker, %{})

      assert count_status_check_jobs(payment.id) == jobs_before
    end
  end

  defp count_status_check_jobs(payment_id) do
    Repo.aggregate(
      from(j in Oban.Job,
        where: j.worker == ^to_string(PaymentStatusCheckWorker),
        where: fragment("args->>'payment_id' = ?", ^payment_id)
      ),
      :count
    )
  end
end
