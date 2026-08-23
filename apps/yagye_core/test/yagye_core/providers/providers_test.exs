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
end
