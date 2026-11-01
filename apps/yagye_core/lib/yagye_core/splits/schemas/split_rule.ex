defmodule YagyeCore.Splits.Schemas.SplitRule do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Splits.Schemas.SplitRuleLeg

  @type t :: %__MODULE__{}

  schema "split_rules" do
    field :public_id, :string
    field :name, :string
    field :description, :string
    field :mode, :string
    field :active, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :merchant, Merchant
    has_many :legs, SplitRuleLeg, foreign_key: :split_rule_id

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[merchant_id name mode]a
  @optional ~w[description active metadata]a

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:mode, ~w[simulation sandbox live])
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:merchant_id)
  end

  defp put_public_id(%{data: %{public_id: nil}} = cs) do
    put_change(cs, :public_id, "srl_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
