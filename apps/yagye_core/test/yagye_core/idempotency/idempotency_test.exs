defmodule YagyeCore.Idempotency.IdempotencyTest do
  # async: false — spawned Tasks need shared sandbox access for the concurrency test
  use YagyeCore.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias YagyeCore.Fixtures
  alias YagyeCore.Idempotency
  alias YagyeCore.Idempotency.Schemas.IdempotencyKey
  alias YagyeCore.Repo

  @fingerprint Base.encode16(:crypto.hash(:sha256, "request-body"))

  defp unique_key, do: "idem-#{System.unique_integer([:positive])}"

  describe "claim/4 state machine" do
    test "returns :claimed for a new key" do
      merchant = Fixtures.approved_merchant_fixture()

      assert {:ok, :claimed, idem_key} =
               Idempotency.claim(merchant.id, unique_key(), @fingerprint)

      assert idem_key.state == "in_progress"
    end

    test "returns :in_progress when the lease is still active" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()

      {:ok, :claimed, _} = Idempotency.claim(merchant.id, key, @fingerprint)

      assert {:error, :in_progress} = Idempotency.claim(merchant.id, key, @fingerprint)
    end

    test "returns :replay after the key is completed" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, key, @fingerprint)
      {:ok, _} = Idempotency.complete(idem_key.id, 201, %{id: "mch_abc"}, "merchant", nil)

      assert {:ok, :replay, replayed} = Idempotency.claim(merchant.id, key, @fingerprint)
      assert replayed.state == "completed"
      assert replayed.response_status == 201
    end

    test "returns :fingerprint_mismatch on completed key with different body" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, key, @fingerprint)
      Idempotency.complete(idem_key.id, 200, %{}, "merchant", nil)

      different_fingerprint = Base.encode16(:crypto.hash(:sha256, "different-body"))

      assert {:error, :fingerprint_mismatch} =
               Idempotency.claim(merchant.id, key, different_fingerprint)
    end

    test "returns :previous_attempt_failed after a failed key" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, key, @fingerprint)
      Idempotency.fail(idem_key.id)

      assert {:error, :previous_attempt_failed} =
               Idempotency.claim(merchant.id, key, @fingerprint)
    end

    test "different merchants can use the same key string independently" do
      merchant_a = Fixtures.approved_merchant_fixture()
      merchant_b = Fixtures.approved_merchant_fixture()
      key = "shared-key-name"

      assert {:ok, :claimed, _} = Idempotency.claim(merchant_a.id, key, @fingerprint)
      assert {:ok, :claimed, _} = Idempotency.claim(merchant_b.id, key, @fingerprint)
    end
  end

  describe "idempotency_keys DB record persistence" do
    test "claim/4 writes a row with the correct fields" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, key, @fingerprint)

      row = Repo.get!(IdempotencyKey, idem_key.id)
      assert row.merchant_id == merchant.id
      assert row.key == key
      assert row.request_fingerprint == @fingerprint
      assert row.state == "in_progress"
      refute is_nil(row.expires_at)
      refute is_nil(row.lease_expires_at)
    end

    test "complete/5 persists state, response fields, and executed_at" do
      merchant = Fixtures.approved_merchant_fixture()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, unique_key(), @fingerprint)

      {:ok, completed} =
        Idempotency.complete(idem_key.id, 201, %{"id" => "pay_abc"}, "payment", nil)

      assert completed.state == "completed"
      assert completed.response_status == 201
      assert completed.response_body == %{"id" => "pay_abc"}
      assert completed.resource_type == "payment"
      refute is_nil(completed.executed_at)
    end

    test "fail/1 sets state to failed" do
      merchant = Fixtures.approved_merchant_fixture()

      {:ok, :claimed, idem_key} = Idempotency.claim(merchant.id, unique_key(), @fingerprint)
      {:ok, failed} = Idempotency.fail(idem_key.id)

      assert failed.state == "failed"
    end

    test "claim/4 with command_name persists it on the row" do
      merchant = Fixtures.approved_merchant_fixture()

      {:ok, :claimed, idem_key} =
        Idempotency.claim(merchant.id, unique_key(), @fingerprint, "CreatePayment")

      row = Repo.get!(IdempotencyKey, idem_key.id)
      assert row.command_name == "CreatePayment"
    end
  end

  describe "claim/4 concurrency" do
    test "exactly one of 50 concurrent claims wins; all others see :in_progress" do
      merchant = Fixtures.approved_merchant_fixture()
      key = unique_key()
      parent = self()

      results =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Sandbox.allow(YagyeCore.Repo, parent, self())
            Idempotency.claim(merchant.id, key, @fingerprint)
          end)
        end)
        |> Task.await_many(10_000)

      claimed = Enum.filter(results, &match?({:ok, :claimed, _}, &1))
      in_progress = Enum.filter(results, &match?({:error, :in_progress}, &1))

      assert length(claimed) == 1
      assert length(in_progress) == 49
    end
  end
end
