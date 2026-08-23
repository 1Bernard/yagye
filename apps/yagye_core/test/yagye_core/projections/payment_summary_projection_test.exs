defmodule YagyeCore.Projections.PaymentSummaryProjectionTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Projections.Schemas.PaymentSummary
  alias YagyeCore.Projections.Workers.PaymentSummaryProjection
  alias YagyeCore.Repo

  defp perform(envelope_map) do
    PaymentSummaryProjection.perform(%Oban.Job{args: %{"envelope" => envelope_map}})
  end

  defp envelope(overrides \\ %{}) do
    merchant = Fixtures.approved_merchant_fixture()
    payment_id = Uniq.UUID.uuid7()

    base = %{
      "event_id" => Uniq.UUID.uuid7(),
      "event_type" => "payment.created",
      "event_version" => 1,
      "aggregate_type" => "payment",
      "aggregate_id" => payment_id,
      "aggregate_version" => 0,
      "merchant_id" => merchant.id,
      "mode" => "simulation",
      "correlation_id" => nil,
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "payload" => %{"method" => "mobile_money", "amount" => 1000, "currency" => "GHS"}
    }

    Map.merge(base, overrides)
  end

  describe "payment.created" do
    test "inserts a proj_payment_summaries row" do
      env = envelope()
      assert :ok = perform(env)

      summary = Repo.get!(PaymentSummary, env["aggregate_id"])
      assert summary.state == "created"
      assert summary.amount == 1000
      assert summary.currency == "GHS"
      assert summary.last_event_id == env["event_id"]
    end

    test "is idempotent — replaying the same event is a no-op" do
      env = envelope()
      assert :ok = perform(env)
      assert :ok = perform(env)

      count =
        Repo.aggregate(
          from(s in PaymentSummary, where: s.payment_id == ^env["aggregate_id"]),
          :count
        )

      assert count == 1
    end
  end

  describe "version fencing" do
    test "applies a newer event" do
      created = envelope(%{"event_type" => "payment.created", "aggregate_version" => 0})

      succeeded =
        envelope(%{
          "aggregate_id" => created["aggregate_id"],
          "event_type" => "payment.succeeded",
          "aggregate_version" => 2,
          "payload" => %{"currency" => "GHS", "net_amount" => 950}
        })

      assert :ok = perform(created)
      assert :ok = perform(succeeded)

      summary = Repo.get!(PaymentSummary, created["aggregate_id"])
      assert summary.state == "succeeded"
      assert summary.aggregate_version == 2
    end

    test "ignores an older event arriving after a newer one is already projected" do
      payment_id = Uniq.UUID.uuid7()
      merchant = Fixtures.approved_merchant_fixture()

      created =
        envelope(%{
          "aggregate_id" => payment_id,
          "merchant_id" => merchant.id,
          "event_type" => "payment.created",
          "aggregate_version" => 0,
          "payload" => %{"method" => "mobile_money", "amount" => 1000, "currency" => "GHS"}
        })

      succeeded =
        envelope(%{
          "aggregate_id" => payment_id,
          "merchant_id" => merchant.id,
          "event_type" => "payment.succeeded",
          "aggregate_version" => 3,
          "payload" => %{"method" => "mobile_money", "amount" => 1000, "currency" => "GHS"}
        })

      # Apply in correct order first
      assert :ok = perform(created)
      assert :ok = perform(succeeded)

      # Now replay the older created event (simulating a duplicate delivery)
      assert :ok = perform(created)

      summary = Repo.get!(PaymentSummary, payment_id)
      # Version fence: older event must not overwrite the newer succeeded state
      assert summary.state == "succeeded"
      assert summary.aggregate_version == 3
    end
  end
end
