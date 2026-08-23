defmodule YagyeCore.Payouts.Schemas.Payout do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payouts.Schemas.PayoutDestination

  @valid_states ~w[scheduled validating reserving submitted paid returned failed cancelled]
  @valid_destination_types ~w[bank mobile_money]
  @public_id_prefix "pot_"

  @type t :: %__MODULE__{}

  schema "payouts" do
    field :public_id, :string
    field :mode, :string
    field :amount, :integer
    field :currency, :string
    field :destination_type, :string
    field :destination_fingerprint, :string
    field :state, :string, default: "scheduled"
    field :provider_reference, :string
    field :scheduled_for, :date
    field :submitted_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :failure_code, :string
    field :returned_at, :utc_datetime_usec
    field :saga_state, :map, default: %{}
    field :requested_by, :string
    field :approved_by, :string

    belongs_to :merchant, Merchant
    belongs_to :destination, PayoutDestination

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(payout, attrs) do
    payout
    |> cast(attrs, [
      :merchant_id,
      :destination_id,
      :mode,
      :amount,
      :currency,
      :destination_type,
      :destination_fingerprint,
      :scheduled_for,
      :requested_by
    ])
    |> validate_required([
      :merchant_id,
      :destination_id,
      :mode,
      :amount,
      :currency,
      :destination_type,
      :destination_fingerprint,
      :scheduled_for
    ])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> validate_inclusion(:mode, ~w[simulation live])
    |> validate_inclusion(:destination_type, @valid_destination_types)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:destination_id)
    |> unique_constraint(:public_id)
    |> put_public_id()
  end

  def transition_changeset(payout, to_state, extra \\ %{})
      when to_state in @valid_states do
    payout
    |> cast(extra, [
      :provider_reference,
      :submitted_at,
      :completed_at,
      :failure_code,
      :returned_at,
      :saga_state
    ])
    |> put_change(:state, to_state)
  end

  def approve_changeset(payout, approved_by) do
    payout
    |> cast(%{approved_by: approved_by}, [:approved_by])
    |> validate_required([:approved_by])
    |> validate_sod()
  end

  defp validate_sod(%{valid?: false} = cs), do: cs

  defp validate_sod(cs) do
    requested_by = get_field(cs, :requested_by)
    approved_by = get_field(cs, :approved_by)

    if requested_by && approved_by && requested_by == approved_by do
      add_error(cs, :approved_by, "must differ from requested_by",
        constraint: :check,
        constraint_name: "payouts_sod_check"
      )
    else
      cs
    end
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs

  def valid_states, do: @valid_states
end
