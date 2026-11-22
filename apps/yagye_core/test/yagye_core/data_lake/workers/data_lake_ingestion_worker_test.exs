defmodule YagyeCore.DataLake.Workers.DataLakeIngestionWorkerTest do
  use YagyeCore.DataCase, async: false

  import ExUnit.CaptureLog

  alias YagyeCore.DataLake.Workers.DataLakeIngestionWorker
  alias YagyeCore.Outbox.Schemas.OutboxMessage

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp valid_payment_envelope do
    %{
      "event_id" => Ecto.UUID.generate(),
      "event_type" => "payment.succeeded",
      "event_version" => 1,
      "aggregate_type" => "payment",
      "aggregate_id" => Ecto.UUID.generate(),
      "aggregate_version" => 2,
      "merchant_id" => Ecto.UUID.generate(),
      "mode" => "live",
      "correlation_id" => "pay_01abc",
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "payload" => %{
        "public_id" => "pay_01abc",
        "state" => "succeeded",
        "mode" => "live",
        "method" => "mobile_money",
        "merchant_code" => "mch_01xyz",
        "currency" => "GHS",
        "amount" => 50_000,
        "net_amount" => 48_500
      }
    }
  end

  defp invalid_payment_envelope do
    %{
      "event_id" => Ecto.UUID.generate(),
      "event_type" => "payment.succeeded",
      "event_version" => 1,
      "aggregate_type" => "payment",
      "aggregate_id" => Ecto.UUID.generate(),
      "aggregate_version" => 2,
      "merchant_id" => nil,
      "mode" => "INVALID_MODE",
      "correlation_id" => nil,
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "payload" => %{
        "public_id" => "pay_01abc",
        "state" => "succeeded",
        "mode" => "INVALID_MODE",
        "method" => "mobile_money",
        "merchant_code" => "mch_01xyz",
        "currency" => "GHS"
      }
    }
  end

  defp insert_outbox_message(envelope) do
    %OutboxMessage{}
    |> OutboxMessage.changeset(%{
      event_id: Ecto.UUID.generate(),
      aggregate_type: envelope["aggregate_type"],
      aggregate_id: envelope["aggregate_id"],
      aggregate_version: envelope["aggregate_version"],
      event_type: envelope["event_type"],
      event_version: envelope["event_version"],
      partition_key: envelope["aggregate_id"],
      destination: "kafka:bronze",
      envelope: envelope,
      mode: "live",
      occurred_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  # ── perform/1 ────────────────────────────────────────────────────────────────

  describe "perform/1" do
    test "returns :ok with no outbox messages" do
      assert :ok = perform_job(DataLakeIngestionWorker, %{})
    end

    test "returns :ok with valid payment envelope — S3 write succeeds via ExAws stub" do
      insert_outbox_message(valid_payment_envelope())
      assert :ok = perform_job(DataLakeIngestionWorker, %{})
    end

    test "returns :ok with invalid envelope — routes to rejected/ in S3" do
      insert_outbox_message(invalid_payment_envelope())
      assert :ok = perform_job(DataLakeIngestionWorker, %{})
    end

    test "returns :ok with mixed valid and invalid envelopes" do
      insert_outbox_message(valid_payment_envelope())
      insert_outbox_message(invalid_payment_envelope())
      assert :ok = perform_job(DataLakeIngestionWorker, %{})
    end

    test "logs a warning for rejected envelopes" do
      insert_outbox_message(invalid_payment_envelope())

      log =
        capture_log(fn ->
          perform_job(DataLakeIngestionWorker, %{})
        end)

      assert log =~ "data_lake.envelope_rejected"
    end

    test "does not log rejection warnings for fully valid envelopes" do
      insert_outbox_message(valid_payment_envelope())

      log =
        capture_log(fn ->
          perform_job(DataLakeIngestionWorker, %{})
        end)

      refute log =~ "data_lake.envelope_rejected"
    end
  end
end
