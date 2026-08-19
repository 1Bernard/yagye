defmodule YagyeCore.Fixtures do
  @moduledoc false

  alias YagyeCore.Merchants

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
