defmodule YagyeCore.Payments.Workers.StuckPaymentScannerWorkerTest do
  use YagyeCore.DataCase, async: true

  import Ecto.Query

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Workers.{PaymentDispatchWorker, StuckPaymentScannerWorker}

  setup do
    merchant = Fixtures.merchant_fixture()
    %{merchant: merchant}
  end

  test "re-enqueues dispatch worker for old processing payments", %{merchant: merchant} do
    payment = Fixtures.payment_fixture(merchant)
    {:ok, processing} = payment |> Payment.transition_changeset("processing") |> Repo.update()

    # Back-date inserted_at via Ecto so the payment appears older than the 5-minute threshold
    Repo.update_all(
      from(p in Payment, where: p.id == ^processing.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -6 * 60, :second)]
    )

    # Clear the fixture's dispatch job so assert_enqueued only sees the scanner's output
    Repo.delete_all(
      from(j in Oban.Job,
        where: j.worker == ^to_string(PaymentDispatchWorker),
        where: fragment("args->>'payment_id' = ?", ^processing.id)
      )
    )

    assert :ok = perform_job(StuckPaymentScannerWorker, %{})

    assert_enqueued(worker: PaymentDispatchWorker, args: %{"payment_id" => processing.id})
  end

  test "ignores processing payments younger than threshold", %{merchant: merchant} do
    payment = Fixtures.payment_fixture(merchant)
    {:ok, processing} = payment |> Payment.transition_changeset("processing") |> Repo.update()

    jobs_before =
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^to_string(PaymentDispatchWorker),
          where: fragment("args->>'payment_id' = ?", ^processing.id)
        ),
        :count
      )

    assert :ok = perform_job(StuckPaymentScannerWorker, %{})

    jobs_after =
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^to_string(PaymentDispatchWorker),
          where: fragment("args->>'payment_id' = ?", ^processing.id)
        ),
        :count
      )

    # Scanner must not have added extra dispatch jobs for this new (< 5 min old) payment
    assert jobs_after == jobs_before
  end

  test "ignores payments in non-processing states", %{merchant: merchant} do
    payment = Fixtures.payment_fixture(merchant)
    {:ok, succeeded} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()

    Repo.update_all(
      from(p in Payment, where: p.id == ^succeeded.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -10 * 60, :second)]
    )

    jobs_before =
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^to_string(PaymentDispatchWorker),
          where: fragment("args->>'payment_id' = ?", ^succeeded.id)
        ),
        :count
      )

    assert :ok = perform_job(StuckPaymentScannerWorker, %{})

    jobs_after =
      Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == ^to_string(PaymentDispatchWorker),
          where: fragment("args->>'payment_id' = ?", ^succeeded.id)
        ),
        :count
      )

    # Scanner must not have added extra dispatch jobs for the succeeded payment
    assert jobs_after == jobs_before
  end
end
