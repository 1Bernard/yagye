defmodule YagyeCore.Splits.Schemas.SplitRuleLeg do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Splits.Schemas.SplitRule

  @valid_split_types ~w[percentage flat]

  @type t :: %__MODULE__{}

  schema "split_rule_legs" do
    field :public_id, :string
    field :label, :string
    field :split_type, :string
    field :value, :integer
    field :rank, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :split_rule, SplitRule
    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[split_rule_id merchant_id label split_type value]a
  @optional ~w[rank metadata]a

  def changeset(leg, attrs) do
    leg
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:split_type, @valid_split_types)
    |> validate_number(:value, greater_than: 0)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:split_rule_id)
    |> foreign_key_constraint(:merchant_id)
  end

  defp put_public_id(%{data: %{public_id: nil}} = cs) do
    put_change(cs, :public_id, "sll_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
