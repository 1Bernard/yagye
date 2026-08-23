defmodule YagyeCore.Events.EventsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Events
  alias YagyeCore.Events.Schemas.OutboxMessage
  alias YagyeCore.Fixtures
  alias YagyeCore.Repo

  # Minimal aggregate struct that mimics a Payment for emit/3
  defp payment_fixture do
    merchant = Fixtures.approved_merchant_fixture()

    %{
      __struct__: YagyeCore.Payments.Schemas.Payment,
      id: Uniq.UUID.uuid7(),
      merchant_id: merchant.id,
      mode: "simulation",
      version: 1
    }
  end

  describe "emit/3" do
    test "inserts an outbox_messages row inside a transaction" do
      payment = payment_fixture()

      Repo.transaction(fn ->
        {:ok, msg} = Events.emit(payment, "payment.created", %{amount: 1000, currency: "GHS"})

        assert msg.event_type == "payment.created"
        assert msg.aggregate_type == "payment"
        assert msg.mode == "simulation"
        assert msg.published_at == nil
        assert msg.publish_attempts == 0
        assert is_integer(msg.id)
      end)
    end

    test "outbox row persists after transaction commits" do
      payment = payment_fixture()

      {:ok, _} =
        Repo.transaction(fn ->
          Events.emit(payment, "payment.succeeded", %{amount: 1000, currency: "GHS"})
        end)

      count = Repo.aggregate(OutboxMessage, :count)
      assert count >= 1
    end

    test "outbox row is rolled back when transaction rolls back" do
      payment = payment_fixture()
      before_count = Repo.aggregate(OutboxMessage, :count)

      Repo.transaction(fn ->
        {:ok, _} = Events.emit(payment, "payment.created", %{})
        Repo.rollback(:intentional)
      end)

      assert Repo.aggregate(OutboxMessage, :count) == before_count
    end

    test "event_id is unique across two emits" do
      payment = payment_fixture()

      {:ok, msg1} =
        Repo.transaction(fn ->
          {:ok, msg} = Events.emit(payment, "payment.created", %{})
          msg
        end)

      {:ok, msg2} =
        Repo.transaction(fn ->
          {:ok, msg} = Events.emit(payment, "payment.succeeded", %{})
          msg
        end)

      refute msg1.event_id == msg2.event_id
    end

    test "envelope JSONB contains the payload" do
      payment = payment_fixture()

      {:ok, msg} =
        Repo.transaction(fn ->
          {:ok, m} = Events.emit(payment, "payment.created", %{amount: 5000, currency: "GHS"})
          m
        end)

      assert msg.envelope["payload"]["amount"] == 5000
      assert msg.envelope["payload"]["currency"] == "GHS"
      assert msg.envelope["event_type"] == "payment.created"
      assert is_binary(msg.envelope["event_id"])
    end

    test "destination defaults to internal:projections" do
      payment = payment_fixture()

      {:ok, msg} =
        Repo.transaction(fn ->
          {:ok, m} = Events.emit(payment, "payment.created", %{})
          m
        end)

      assert msg.destination == "internal:projections"
    end

    test "rejects unknown destination" do
      payment = payment_fixture()

      Repo.transaction(fn ->
        {:error, changeset} =
          Events.emit(payment, "payment.created", %{}, destination: "unknown:nowhere")

        assert "is invalid" in errors_on(changeset).destination
        Repo.rollback(:expected)
      end)
    end
  end
end
