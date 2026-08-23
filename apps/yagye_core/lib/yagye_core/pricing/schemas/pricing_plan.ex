defmodule YagyeCore.Pricing.Schemas.PricingPlan do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_fee_modes ~w[deducted invoiced]
  @valid_modes ~w[simulation live]
  @public_id_prefix "plan_"

  @type t :: %__MODULE__{}

  schema "pricing_plans" do
    field(:public_id, :string)
    field(:name, :string)
    field(:version, :integer)
    field(:currency, :string)
    field(:fee_mode, :string)
    field(:effective_from, :utc_datetime_usec)
    field(:effective_to, :utc_datetime_usec)
    field(:monthly_fee, :integer, default: 0)

    has_many(:rules, YagyeCore.Pricing.Schemas.PricingRule, foreign_key: :plan_id)

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def create_changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :version,
      :currency,
      :fee_mode,
      :effective_from,
      :effective_to,
      :monthly_fee
    ])
    |> validate_required([:name, :version, :currency, :fee_mode, :effective_from])
    |> validate_inclusion(:fee_mode, @valid_fee_modes)
    |> validate_length(:currency, is: 3)
    |> validate_number(:monthly_fee, greater_than_or_equal_to: 0)
    |> validate_number(:version, greater_than_or_equal_to: 1)
    |> unique_constraint(:public_id)
    |> unique_constraint([:name, :version])
    |> put_public_id()
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs

  def valid_fee_modes, do: @valid_fee_modes
  def valid_modes, do: @valid_modes
end
