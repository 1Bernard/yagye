defmodule YagyeCore.Risk.Schemas.RiskLabel do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @valid_labels ~w[confirmed_fraud false_positive suspicious legitimate]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "risk_labels" do
    field :label, :string
    field :labelled_by, :string
    field :note, :string

    belongs_to :payment, YagyeCore.Payments.Schemas.Payment

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:payment_id, :label, :labelled_by, :note])
    |> validate_required([:payment_id, :label, :labelled_by])
    |> validate_inclusion(:label, @valid_labels)
    |> foreign_key_constraint(:payment_id)
  end
end
