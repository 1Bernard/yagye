defmodule YagyeCore.Settlement.Schemas.Settlement do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider

  @valid_states ~w[expected reported matching matched mismatched investigating settled written_off]
  @public_id_prefix "stl_"

  @type t :: %__MODULE__{}

  schema "settlements" do
    field :public_id, :string
    field :mode, :string
    field :currency, :string
    field :period_start, :utc_datetime_usec
    field :period_end, :utc_datetime_usec
    field :state, :string, default: "expected"
    field :expected_gross, :integer
    field :expected_provider_fees, :integer
    field :expected_platform_fees, :integer
    field :expected_refunds, :integer
    field :expected_chargebacks, :integer
    field :expected_net, :integer
    field :reported_gross, :integer
    field :reported_fees, :integer
    field :reported_net, :integer
    field :actual_received, :integer
    # variance is a generated column — read-only, never cast
    field :variance, :integer, virtual: false
    field :provider_settlement_reference, :string
    field :value_date, :date
    field :reconciliation_run_id, :binary_id

    belongs_to :merchant, Merchant
    belongs_to :provider, Provider

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(settlement, attrs) do
    settlement
    |> cast(attrs, [
      :merchant_id,
      :provider_id,
      :mode,
      :currency,
      :period_start,
      :period_end,
      :expected_gross,
      :expected_provider_fees,
      :expected_platform_fees,
      :expected_refunds,
      :expected_chargebacks,
      :expected_net
    ])
    |> validate_required([
      :merchant_id,
      :provider_id,
      :mode,
      :currency,
      :period_start,
      :period_end,
      :expected_gross,
      :expected_provider_fees,
      :expected_platform_fees,
      :expected_refunds,
      :expected_chargebacks,
      :expected_net
    ])
    |> validate_length(:currency, is: 3)
    |> validate_inclusion(:mode, ~w[simulation live])
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint(
      [:merchant_id, :provider_id, :mode, :currency, :period_start, :period_end],
      name: :settlements_merchant_id_provider_id_mode_currency_period_start_
    )
    |> unique_constraint(:public_id)
    |> put_public_id()
  end

  def transition_changeset(settlement, to_state, extra \\ %{})
      when to_state in @valid_states do
    settlement
    |> cast(extra, [
      :reported_gross,
      :reported_fees,
      :reported_net,
      :actual_received,
      :provider_settlement_reference,
      :value_date,
      :reconciliation_run_id
    ])
    |> put_change(:state, to_state)
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs

  def valid_states, do: @valid_states
end
