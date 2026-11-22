defmodule YagyeCore.DataLake.SchemaRegistryTest do
  use ExUnit.Case, async: true

  alias YagyeCore.DataLake.SchemaRegistry

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
      "occurred_at" => "2026-11-22T10:00:00Z",
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

  defp valid_settlement_envelope do
    %{
      "event_id" => Ecto.UUID.generate(),
      "event_type" => "settlement.batch.settled",
      "event_version" => 1,
      "aggregate_type" => "settlement_batch",
      "aggregate_id" => Ecto.UUID.generate(),
      "aggregate_version" => 5,
      "merchant_id" => Ecto.UUID.generate(),
      "mode" => "live",
      "correlation_id" => nil,
      "occurred_at" => "2026-11-22T10:00:00Z",
      "payload" => %{
        "public_id" => "stl_01xyz",
        "merchant_code" => "mch_01xyz",
        "currency" => "GHS",
        "gross_amount" => 500_000,
        "fee_amount" => 7_500,
        "net_amount" => 492_500,
        "payment_count" => 10
      }
    }
  end

  # ── validate/1 ───────────────────────────────────────────────────────────────

  describe "validate/1 — payment events" do
    test "accepts a fully valid payment envelope" do
      assert SchemaRegistry.validate(valid_payment_envelope()) == :ok
    end

    test "accepts sandbox mode" do
      env =
        Map.merge(valid_payment_envelope(), %{
          "mode" => "sandbox",
          "payload" => Map.merge(valid_payment_envelope()["payload"], %{"mode" => "sandbox"})
        })

      assert SchemaRegistry.validate(env) == :ok
    end

    test "rejects unknown mode value" do
      env = Map.put(valid_payment_envelope(), "mode", "test")
      assert {:error, _} = SchemaRegistry.validate(env)
    end

    test "rejects missing required envelope field event_id" do
      env = Map.delete(valid_payment_envelope(), "event_id")
      assert {:error, _} = SchemaRegistry.validate(env)
    end

    test "rejects missing required payload field merchant_code" do
      env = put_in(valid_payment_envelope(), ["payload", "merchant_code"], nil)
      # merchant_code is required in payment schema payload — nil fails minLength
      assert {:error, _} = SchemaRegistry.validate(env)
    end

    test "rejects extra top-level fields" do
      env = Map.put(valid_payment_envelope(), "extra_field", "not_allowed")
      assert {:error, _} = SchemaRegistry.validate(env)
    end

    test "rejects event_version below 1" do
      env = Map.put(valid_payment_envelope(), "event_version", 0)
      assert {:error, _} = SchemaRegistry.validate(env)
    end
  end

  describe "validate/1 — settlement events" do
    test "accepts a fully valid settlement envelope" do
      assert SchemaRegistry.validate(valid_settlement_envelope()) == :ok
    end

    test "rejects settlement envelope with wrong event_type prefix" do
      env = Map.put(valid_settlement_envelope(), "event_type", "payment.succeeded")
      # event_type pattern ^settlement\. will fail
      assert {:error, _} = SchemaRegistry.validate(env)
    end
  end

  describe "validate/1 — unknown prefix" do
    test "passes through envelopes with no registered schema" do
      env = %{
        "event_id" => Ecto.UUID.generate(),
        "event_type" => "unknown_prefix.created",
        "event_version" => 1,
        "aggregate_type" => "thing",
        "aggregate_id" => Ecto.UUID.generate(),
        "aggregate_version" => 0,
        "merchant_id" => nil,
        "mode" => "live",
        "correlation_id" => nil,
        "occurred_at" => "2026-11-22T10:00:00Z",
        "payload" => %{}
      }

      assert SchemaRegistry.validate(env) == :ok
    end
  end

  describe "validate/1 — missing event_type" do
    test "returns an error when event_type is absent" do
      assert {:error, {:missing_event_type, _}} =
               SchemaRegistry.validate(%{"mode" => "live"})
    end
  end

  # ── families/0 ───────────────────────────────────────────────────────────────

  describe "families/0" do
    test "includes all expected event families" do
      families = SchemaRegistry.families()
      assert "payment" in families
      assert "settlement" in families
      assert "compliance" in families
      assert "merchant" in families
      assert "reconciliation" in families
      assert "dispute" in families
      assert "checkout_session" in families
      assert "payment_link" in families
      assert "webhook" in families
    end
  end
end
