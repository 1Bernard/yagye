defmodule YagyeCore.Fixtures do
  @moduledoc false

  alias YagyeCore.Customers
  alias YagyeCore.Merchants
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

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
    reviewer = "user:reviewer_#{System.unique_integer([:positive])}"
    approver = "user:approver_#{System.unique_integer([:positive])}"
    {:ok, {merchant, _}} = Merchants.submit_basic_info(merchant.public_id, "user:owner")
    {:ok, {merchant, _}} = Merchants.submit_documents(merchant.public_id, "user:owner")
    {:ok, {merchant, _}} = Merchants.start_review(merchant.public_id, reviewer)
    {:ok, {merchant, _}} = Merchants.approve(merchant.public_id, approver)
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
        Map.merge(
          %{amount: 10_000, currency: "GHS", rail: "fiat_provider", method: "mobile_money"},
          attrs
        )
      )

    payment
  end

  def succeeded_payment_fixture(merchant, attrs \\ %{}) do
    payment = payment_fixture(merchant, attrs)
    {:ok, payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
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

  # Creates a fresh provider (unique code) with a platform-level simulation credential
  # that includes a webhook_secret. Returns {provider, secret}.
  # Each call produces a distinct provider so async tests don't share state.
  def webhook_provider_fixture(secret \\ "wh_test_secret_#{System.unique_integer([:positive])}") do
    provider =
      %Provider{}
      |> Provider.changeset(%{
        code: "wh_test_#{System.unique_integer([:positive])}",
        display_name: "Webhook Test Provider",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: true
      })
      |> Repo.insert!()

    payload = %{"api_key" => "test_key", "webhook_secret" => secret}

    %ProviderCredential{}
    |> ProviderCredential.changeset(%{
      provider_id: provider.id,
      merchant_id: nil,
      mode: "simulation",
      base_url: "http://localhost:4100",
      encrypted_payload: Vault.encrypt_map(payload),
      active: true
    })
    |> Repo.insert!()

    {provider, secret}
  end

  def customer_fixture(merchant, attrs \\ %{}) do
    ref = Map.get(attrs, :merchant_customer_ref, "cust_#{System.unique_integer([:positive])}")
    {:ok, customer} = Customers.find_or_create(merchant.id, ref, attrs)
    customer
  end

  def provider_fixture(attrs \\ %{}) do
    %Provider{}
    |> Provider.changeset(
      Map.merge(
        %{
          code: "provider_#{System.unique_integer([:positive])}",
          display_name: "Test Provider",
          adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
          active: true
        },
        attrs
      )
    )
    |> Repo.insert!()
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
