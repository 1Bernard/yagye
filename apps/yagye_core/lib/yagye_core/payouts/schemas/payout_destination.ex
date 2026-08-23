defmodule YagyeCore.Payouts.Schemas.PayoutDestination do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Shared.Vault

  @valid_kinds ~w[bank mobile_money]
  @valid_verification_states ~w[unverified micro_deposit_sent verified failed]
  @public_id_prefix "pdt_"

  @type t :: %__MODULE__{}

  schema "payout_destinations" do
    field :public_id, :string
    field :mode, :string
    field :kind, :string
    field :currency, :string
    field :account_details_encrypted, :binary
    field :fingerprint, :string
    field :account_name_verified, :string
    field :verification_state, :string, default: "unverified"
    field :is_default, :boolean, default: false
    field :active, :boolean, default: true
    field :hold_until, :utc_datetime_usec
    field :added_by, :string
    field :verified_by, :string

    # Virtual — only used during create, never persisted directly
    field :account_details, :map, virtual: true

    belongs_to :merchant, Merchant

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(dest, attrs) do
    dest
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :kind,
      :currency,
      :account_details,
      :account_name_verified,
      :added_by
    ])
    |> validate_required([:merchant_id, :mode, :kind, :currency, :account_details])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_inclusion(:mode, ~w[simulation live])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:merchant_id)
    |> put_encrypted_details()
    |> put_fingerprint()
    |> unique_constraint([:merchant_id, :mode, :fingerprint])
    |> unique_constraint(:public_id)
    |> put_public_id()
  end

  def deactivate_changeset(dest) do
    change(dest, active: false)
  end

  def verify_changeset(dest, verified_by, state \\ "verified")
      when state in @valid_verification_states do
    dest
    |> cast(%{verified_by: verified_by, verification_state: state}, [
      :verified_by,
      :verification_state
    ])
    |> validate_sod()
  end

  def hold_changeset(dest, until) do
    change(dest, hold_until: until)
  end

  defp validate_sod(%{valid?: false} = cs), do: cs

  defp validate_sod(cs) do
    added_by = get_field(cs, :added_by)
    verified_by = get_field(cs, :verified_by)

    if added_by && verified_by && added_by == verified_by do
      add_error(cs, :verified_by, "must differ from added_by",
        constraint: :check,
        constraint_name: "payout_destinations_sod_check"
      )
    else
      cs
    end
  end

  def verification_changeset(dest, state) when state in @valid_verification_states do
    change(dest, verification_state: state)
  end

  defp put_encrypted_details(%{valid?: false} = cs), do: cs

  defp put_encrypted_details(cs) do
    case get_change(cs, :account_details) do
      nil ->
        cs

      details ->
        ciphertext = details |> Jason.encode!() |> Vault.encrypt()
        put_change(cs, :account_details_encrypted, ciphertext)
    end
  end

  defp put_fingerprint(%{valid?: false} = cs), do: cs

  defp put_fingerprint(cs) do
    case get_change(cs, :account_details) do
      nil ->
        cs

      details ->
        canonical = details |> Map.to_list() |> Enum.sort() |> inspect()
        fingerprint = :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
        put_change(cs, :fingerprint, fingerprint)
    end
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs

  def decrypt_details(%__MODULE__{account_details_encrypted: enc}) when not is_nil(enc) do
    case Vault.decrypt(enc) do
      {:ok, plaintext} -> Jason.decode(plaintext)
      error -> error
    end
  end

  def decrypt_details(_), do: {:error, :no_details}
end
