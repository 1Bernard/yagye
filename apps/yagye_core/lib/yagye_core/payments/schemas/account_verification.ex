defmodule YagyeCore.Payments.Schemas.AccountVerification do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_types ~w[mobile_money bank_account]
  @valid_states ~w[pending verified failed]

  @type t :: %__MODULE__{}

  schema "account_verifications" do
    field(:verification_type, :string)
    field(:provider_code, :string)
    field(:account_hash, :string)
    field(:account_masked, :string)
    field(:network, :string)
    field(:bank_code, :string)
    field(:account_name_returned, :string)
    field(:kyc_tier_returned, :string)
    field(:name_match_score, :decimal)
    field(:state, :string, default: "pending")
    field(:raw_response, :map)
    field(:payment_id, :binary_id)

    belongs_to(:merchant, Merchant)

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def create_changeset(verification, attrs) do
    verification
    |> cast(attrs, [
      :merchant_id,
      :payment_id,
      :verification_type,
      :provider_code,
      :account_hash,
      :account_masked,
      :network,
      :bank_code
    ])
    |> validate_required([
      :merchant_id,
      :verification_type,
      :provider_code,
      :account_hash,
      :account_masked
    ])
    |> validate_inclusion(:verification_type, @valid_types)
    |> foreign_key_constraint(:merchant_id)
  end

  def complete_changeset(verification, result) do
    verification
    |> cast(result, [
      :account_name_returned,
      :kyc_tier_returned,
      :name_match_score,
      :state,
      :raw_response
    ])
    |> validate_required([:state])
    |> validate_inclusion(:state, @valid_states)
  end
end
