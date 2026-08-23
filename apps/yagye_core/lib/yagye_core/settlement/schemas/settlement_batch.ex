defmodule YagyeCore.Settlement.Schemas.SettlementBatch do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider

  @valid_states ~w[pending processing settled failed]
  @valid_modes ~w[simulation live]

  @type t :: %__MODULE__{}

  schema "settlement_batches" do
    field :currency, :string
    field :mode, :string
    field :period_start, :utc_datetime_usec
    field :period_end, :utc_datetime_usec
    field :payment_count, :integer, default: 0
    field :gross_amount, :integer, default: 0
    field :state, :string, default: "pending"
    field :error, :string
    field :settled_at, :utc_datetime_usec

    belongs_to :merchant, Merchant
    belongs_to :provider, Provider

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :merchant_id,
      :provider_id,
      :currency,
      :mode,
      :period_start,
      :period_end,
      :payment_count,
      :gross_amount,
      :state,
      :error,
      :settled_at
    ])
    |> validate_required([
      :merchant_id,
      :provider_id,
      :currency,
      :mode,
      :period_start,
      :period_end
    ])
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_length(:currency, is: 3)
    |> validate_number(:payment_count, greater_than_or_equal_to: 0)
    |> validate_number(:gross_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint(
      [:merchant_id, :provider_id, :currency, :mode, :period_start, :period_end],
      name: :settlement_batches_merchant_id_provider_id_currency_mode_period
    )
  end

  def transition_changeset(batch, to_state) when to_state in @valid_states do
    change(batch, state: to_state)
  end

  def valid_states, do: @valid_states
end
