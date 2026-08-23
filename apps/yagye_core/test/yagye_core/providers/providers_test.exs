defmodule YagyeCore.Providers.ProvidersTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Providers.Schemas.Provider

  describe "Provider.changeset/2" do
    test "valid with kind: native_rail" do
      changeset =
        Provider.changeset(%Provider{}, %{
          code: "mtn",
          display_name: "MTN Mobile Money",
          adapter_module: "YagyeCore.Payments.Adapters.Mtn",
          kind: "native_rail"
        })

      assert changeset.valid?
    end

    test "valid with kind: external_psp" do
      changeset =
        Provider.changeset(%Provider{}, %{
          code: "stripe",
          display_name: "Stripe",
          adapter_module: "YagyeCore.Payments.Adapters.Stripe",
          kind: "external_psp"
        })

      assert changeset.valid?
    end

    test "rejects unknown kind" do
      changeset =
        Provider.changeset(%Provider{}, %{
          code: "x",
          display_name: "X",
          adapter_module: "X.Adapter",
          kind: "orchestrator"
        })

      assert "is invalid" in errors_on(changeset).kind
    end

    test "requires kind when explicitly nil" do
      changeset =
        Provider.changeset(%Provider{}, %{
          code: "x",
          display_name: "X",
          adapter_module: "X.Adapter",
          kind: nil
        })

      assert "can't be blank" in errors_on(changeset).kind
    end

    test "defaults to native_rail when kind not provided" do
      changeset =
        Provider.changeset(%Provider{}, %{
          code: "mtn",
          display_name: "MTN Mobile Money",
          adapter_module: "YagyeCore.Payments.Adapters.Mtn"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :kind) == "native_rail"
    end
  end

  describe "Provider.changeset/2 — settlement_cadence" do
    defp base_attrs do
      %{code: "mtn", display_name: "MTN MoMo", adapter_module: "X.Adapter", kind: "native_rail"}
    end

    test "accepts empty map (platform default)" do
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, %{}))
      assert cs.valid?
    end

    test "accepts valid cutoff_hour and timezone" do
      cadence = %{"cutoff_hour" => 22, "timezone" => "Africa/Accra"}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert cs.valid?
    end

    test "accepts cutoff_hour 0 (midnight)" do
      cadence = %{"cutoff_hour" => 0, "timezone" => "Africa/Lagos"}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert cs.valid?
    end

    test "rejects cutoff_hour > 23" do
      cadence = %{"cutoff_hour" => 24, "timezone" => "Africa/Accra"}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert errors_on(cs).settlement_cadence != []
    end

    test "rejects cutoff_hour that is not an integer" do
      cadence = %{"cutoff_hour" => "23", "timezone" => "Africa/Accra"}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert errors_on(cs).settlement_cadence != []
    end

    test "rejects missing timezone" do
      cadence = %{"cutoff_hour" => 22}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert errors_on(cs).settlement_cadence != []
    end

    test "rejects empty string timezone" do
      cadence = %{"cutoff_hour" => 22, "timezone" => ""}
      cs = Provider.changeset(%Provider{}, Map.put(base_attrs(), :settlement_cadence, cadence))
      assert errors_on(cs).settlement_cadence != []
    end

    test "unchanged settlement_cadence is not re-validated" do
      existing = %Provider{
        code: "mtn",
        display_name: "MTN MoMo",
        adapter_module: "X.Adapter",
        kind: "native_rail",
        settlement_cadence: %{"cutoff_hour" => 22, "timezone" => "Africa/Accra"}
      }

      cs = Provider.changeset(existing, %{display_name: "New Name"})
      assert cs.valid?
      assert errors_on(cs)[:settlement_cadence] == nil
    end
  end
end
