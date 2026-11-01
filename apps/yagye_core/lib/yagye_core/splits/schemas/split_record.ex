defmodule YagyeCore.Splits.Schemas.SplitRecord do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Splits.Schemas.{SplitRule, SplitRuleLeg}

  @valid_states ~w[pending settled failed]

  @type t :: %__MODULE__{}

  schema "split_records" do
    field :public_id, :string
    field :amount, :integer
    field :currency, :string
    field :mode, :string
    field :state, :string, default: "pending"
    field :settled_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :payment, Payment
    belongs_to :split_rule, SplitRule
    belongs_to :split_rule_leg, SplitRuleLeg
    belongs_to :merchant, Merchant

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[payment_id split_rule_id split_rule_leg_id merchant_id amount currency mode]a
  @optional ~w[settled_at metadata]a

  def changeset(record, attrs) do
    record
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:mode, ~w[simulation sandbox live])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:split_rule_id)
    |> foreign_key_constraint(:split_rule_leg_id)
    |> foreign_key_constraint(:merchant_id)
  end

  def transition_changeset(record, to_state) when to_state in @valid_states do
    change(record, state: to_state)
  end

  defp put_public_id(%{data: %{public_id: nil}} = cs) do
    put_change(cs, :public_id, "spr_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
