defmodule YagyeCore.Reserves.Schemas.MerchantReserve do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_kinds ~w[rolling fixed ad_hoc]
  @valid_modes ~w[simulation live]

  @type t :: %__MODULE__{}

  schema "merchant_reserves" do
    field :mode, :string
    field :kind, :string
    field :percentage_bps, :integer
    field :fixed_amount, :integer
    field :currency, :string
    field :hold_days, :integer
    field :active, :boolean, default: true
    field :reason, :string
    field :created_by, :string
    field :approved_by, :string

    belongs_to :merchant, Merchant

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(reserve, attrs) do
    reserve
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :kind,
      :percentage_bps,
      :fixed_amount,
      :currency,
      :hold_days,
      :reason,
      :created_by
    ])
    |> validate_required([:merchant_id, :mode, :kind, :currency])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_length(:currency, is: 3)
    |> validate_kind_fields()
    |> validate_number(:percentage_bps, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:fixed_amount, greater_than: 0)
    |> validate_number(:hold_days, greater_than: 0)
    |> foreign_key_constraint(:merchant_id)
  end

  def approve_changeset(reserve, approved_by) do
    reserve
    |> cast(%{approved_by: approved_by}, [:approved_by])
    |> validate_required([:approved_by])
    |> validate_sod()
  end

  defp validate_sod(%{valid?: false} = cs), do: cs

  defp validate_sod(cs) do
    created_by = get_field(cs, :created_by)
    approved_by = get_field(cs, :approved_by)

    if created_by && approved_by && created_by == approved_by do
      add_error(cs, :approved_by, "must differ from created_by",
        constraint: :check,
        constraint_name: "merchant_reserves_sod_check"
      )
    else
      cs
    end
  end

  def deactivate_changeset(reserve) do
    change(reserve, active: false)
  end

  defp validate_kind_fields(%{valid?: false} = cs), do: cs

  defp validate_kind_fields(cs) do
    case get_field(cs, :kind) do
      "rolling" ->
        validate_required(cs, [:percentage_bps, :hold_days])

      "fixed" ->
        validate_required(cs, [:fixed_amount])

      _ ->
        cs
    end
  end

  def valid_kinds, do: @valid_kinds
end
