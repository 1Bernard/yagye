defmodule YagyeCore.Fixtures do
  @moduledoc false

  alias YagyeCore.Merchants
  alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
  alias YagyeCore.Shared.Vault
  alias YagyeCore.Repo

  def merchant_fixture(attrs \\ %{}) do
    {:ok, {merchant, _}} =
      Merchants.create_merchant(
        Map.merge(
          %{
            legal_name: "Test Merchant #{System.unique_integer([:positive])}",
            trading_name: "Test Co",
            country: "GB",
            default_currency: "GBP"
          },
          attrs
        )
      )

    merchant
  end

  def approved_merchant_fixture(attrs \\ %{}) do
    merchant = merchant_fixture(attrs)
    {:ok, {merchant, _}} = Merchants.approve(merchant.public_id, merchant.id)
    merchant
  end

  # Inserts a pii_vault row and returns the subject_ref UUID string.
  # Required before creating a BeneficialOwner (FK constraint).
  def pii_vault_fixture(attrs \\ %{}) do
    subject_ref = Map.get(attrs, :subject_ref, Uniq.UUID.uuid7())
    kind = Map.get(attrs, :subject_kind, "beneficial_owner")

    {:ok, subject_ref_bin} = Ecto.UUID.dump(subject_ref)

    YagyeCore.Repo.query!(
      "INSERT INTO pii_vault (subject_ref, kms_key_id, ciphertext, subject_kind, inserted_at) VALUES ($1, $2, $3, $4, $5)",
      [subject_ref_bin, "test-kms-key", <<0>>, kind, DateTime.utc_now()]
    )

    subject_ref
  end

  def payment_fixture(merchant, attrs \\ %{}) do
    {:ok, {payment, _event}} =
      YagyeCore.Payments.create_payment(
        merchant.id,
        Map.merge(%{amount: 10_000, currency: "GHS", rail: "fiat_provider"}, attrs)
      )

    payment
  end

  def simulator_provider_fixture do
    case Repo.get_by(Provider, code: "simulator") do
      %Provider{} = p ->
        p

      nil ->
        %Provider{}
        |> Provider.changeset(%{
          code: "simulator",
          display_name: "Gateway Simulator",
          adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
          active: true
        })
        |> Repo.insert!()
    end
  end

  # Platform-level simulator credential (merchant_id = nil).
  # Returns the decrypted credential map as the Providers context would deliver it.
  def simulator_credential_fixture(provider) do
    payload = %{"api_key" => "sim_test_key"}
    base_url = "http://localhost:4100"

    case Repo.get_by(ProviderCredential, provider_id: provider.id, mode: "simulation") do
      %ProviderCredential{} ->
        :ok

      nil ->
        %ProviderCredential{}
        |> ProviderCredential.changeset(%{
          provider_id: provider.id,
          merchant_id: nil,
          mode: "simulation",
          base_url: base_url,
          encrypted_payload: Vault.encrypt_map(payload),
          active: true
        })
        |> Repo.insert!()
    end

    Map.put(payload, "base_url", base_url)
  end

  # Returns {api_key, raw_key}. raw_key is only available at creation.
  def api_key_fixture(merchant, attrs \\ %{}) do
    {:ok, {api_key, raw_key, _}} =
      Merchants.issue_api_key(
        merchant.public_id,
        Map.merge(%{kind: "secret", mode: "simulation", scopes: ["*"]}, attrs)
      )

    {api_key, raw_key}
  end
end
