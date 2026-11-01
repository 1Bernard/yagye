defmodule YagyeCore.Providers.ProviderConnectionsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Providers
  alias YagyeCore.Providers.Schemas.{MerchantProviderConnection, ProviderCredential}
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.provider_fixture(%{kind: "external_psp"})
    %{merchant: merchant, provider: provider}
  end

  # ── list_merchant_connections/2 ──────────────────────────────────────────────

  describe "list_merchant_connections/2" do
    test "returns empty list when merchant has no connections", %{merchant: merchant} do
      assert {:ok, []} = Providers.list_merchant_connections(merchant.id)
    end

    test "returns all connections for merchant with preloaded provider", %{
      merchant: merchant,
      provider: provider
    } do
      insert_connection(merchant, provider, mode: "sandbox")
      assert {:ok, [conn]} = Providers.list_merchant_connections(merchant.id)
      assert conn.merchant_id == merchant.id
      assert conn.provider.id == provider.id
    end

    test "filters by mode when specified", %{merchant: merchant, provider: provider} do
      provider2 = Fixtures.provider_fixture(%{kind: "external_psp"})
      insert_connection(merchant, provider, mode: "sandbox")
      insert_connection(merchant, provider2, mode: "live")

      assert {:ok, [conn]} = Providers.list_merchant_connections(merchant.id, "sandbox")
      assert conn.mode == "sandbox"
    end

    test "does not return another merchant's connections", %{
      merchant: merchant,
      provider: provider
    } do
      other = Fixtures.merchant_fixture()
      insert_connection(other, provider, mode: "sandbox")

      assert {:ok, []} = Providers.list_merchant_connections(merchant.id)
    end
  end

  # ── create_merchant_connection/3 ─────────────────────────────────────────────

  describe "create_merchant_connection/3" do
    test "creates a connection with correct fields", %{merchant: merchant, provider: provider} do
      assert {:ok, conn} =
               Providers.create_merchant_connection(merchant.id, provider.id, %{
                 mode: "sandbox",
                 priority: 1,
                 enabled_methods: ["mobile_money"],
                 status: "active"
               })

      assert conn.merchant_id == merchant.id
      assert conn.provider_id == provider.id
      assert conn.mode == "sandbox"
      assert conn.priority == 1
      assert conn.status == "active"
      assert conn.provider.id == provider.id
    end

    test "returns existing connection on duplicate (no error)", %{
      merchant: merchant,
      provider: provider
    } do
      {:ok, first} =
        Providers.create_merchant_connection(merchant.id, provider.id, %{
          mode: "sandbox",
          priority: 1
        })

      {:ok, second} =
        Providers.create_merchant_connection(merchant.id, provider.id, %{
          mode: "sandbox",
          priority: 2
        })

      assert first.id == second.id
    end

    test "allows same merchant + provider in different modes", %{
      merchant: merchant,
      provider: provider
    } do
      {:ok, sandbox} =
        Providers.create_merchant_connection(merchant.id, provider.id, %{mode: "sandbox"})

      {:ok, live} =
        Providers.create_merchant_connection(merchant.id, provider.id, %{mode: "live"})

      assert sandbox.id != live.id
    end
  end

  # ── update_merchant_connection/2 ─────────────────────────────────────────────

  describe "update_merchant_connection/2" do
    test "updates priority and status", %{merchant: merchant, provider: provider} do
      conn = insert_connection(merchant, provider, mode: "sandbox", priority: 1)

      assert {:ok, updated} =
               Providers.update_merchant_connection(conn.id, %{priority: 5, status: "paused"})

      assert updated.priority == 5
      assert updated.status == "paused"
    end

    test "returns not_found for unknown id" do
      unknown_uuid = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Providers.update_merchant_connection(unknown_uuid, %{priority: 2})
    end
  end

  # ── deactivate_merchant_connection/1 ─────────────────────────────────────────

  describe "deactivate_merchant_connection/1" do
    test "sets status to disabled", %{merchant: merchant, provider: provider} do
      conn = insert_connection(merchant, provider, mode: "sandbox")
      assert {:ok, deactivated} = Providers.deactivate_merchant_connection(conn.id)
      assert deactivated.status == "disabled"
    end
  end

  # ── store_merchant_credential/4 ──────────────────────────────────────────────

  describe "store_merchant_credential/4" do
    test "stores encrypted credential for merchant", %{merchant: merchant, provider: provider} do
      creds = %{
        "api_key" => "pk_test_abc",
        "secret_key" => "sk_test_xyz",
        "base_url" => "https://api.paystack.co"
      }

      assert {:ok, cred} =
               Providers.store_merchant_credential(provider.id, merchant.id, "sandbox", creds)

      assert cred.provider_id == provider.id
      assert cred.merchant_id == merchant.id
      assert cred.mode == "sandbox"
      assert cred.base_url == "https://api.paystack.co"
      assert is_binary(cred.encrypted_payload)

      {:ok, decrypted} = Vault.decrypt_map(cred.encrypted_payload)
      assert decrypted["api_key"] == "pk_test_abc"
      assert decrypted["secret_key"] == "sk_test_xyz"
    end

    test "upserts on duplicate provider+merchant+mode", %{merchant: merchant, provider: provider} do
      creds1 = %{"api_key" => "old_key", "base_url" => "https://api.paystack.co"}
      {:ok, _} = Providers.store_merchant_credential(provider.id, merchant.id, "sandbox", creds1)

      creds2 = %{"api_key" => "new_key", "base_url" => "https://api.paystack.co"}
      {:ok, _} = Providers.store_merchant_credential(provider.id, merchant.id, "sandbox", creds2)

      count = Repo.aggregate(ProviderCredential, :count)
      assert count == 1

      [cred] = Repo.all(ProviderCredential)
      {:ok, decrypted} = Vault.decrypt_map(cred.encrypted_payload)
      assert decrypted["api_key"] == "new_key"
    end

    test "base_url stored separately not in encrypted payload", %{
      merchant: merchant,
      provider: provider
    } do
      creds = %{"api_key" => "key", "base_url" => "https://example.com"}
      {:ok, cred} = Providers.store_merchant_credential(provider.id, merchant.id, "live", creds)

      assert cred.base_url == "https://example.com"
      {:ok, decrypted} = Vault.decrypt_map(cred.encrypted_payload)
      refute Map.has_key?(decrypted, "base_url")
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp insert_connection(merchant, provider, attrs) do
    defaults = %{mode: "sandbox", priority: 1, status: "active", enabled_methods: []}
    attrs_with_defaults = Map.merge(defaults, Map.new(attrs))

    %MerchantProviderConnection{}
    |> MerchantProviderConnection.changeset(
      Map.merge(attrs_with_defaults, %{merchant_id: merchant.id, provider_id: provider.id})
    )
    |> Repo.insert!()
  end
end
