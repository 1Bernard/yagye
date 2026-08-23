defmodule YagyeCore.Reconciliation.Schemas.ReconciliationMatch do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Reconciliation.Schemas.ReconciliationRun

  @valid_strategies ~w[exact_reference composite amount_window subset_sum]
  # auto-accept anything at or above this confidence threshold
  @auto_accept_threshold Decimal.new("0.950")

  @type t :: %__MODULE__{}

  schema "reconciliation_matches" do
    field :strategy, :string
    field :confidence, :decimal
    field :left_type, :string
    field :left_ids, {:array, :binary_id}
    field :right_type, :string
    field :right_ids, {:array, :binary_id}
    field :amount_left, :integer
    field :amount_right, :integer
    field :currency, :string
    field :auto_accepted, :boolean, default: false
    field :accepted_by, :string
    field :accepted_at, :utc_datetime_usec

    belongs_to :run, ReconciliationRun

    timestamps(updated_at: false)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :run_id,
      :strategy,
      :confidence,
      :left_type,
      :left_ids,
      :right_type,
      :right_ids,
      :amount_left,
      :amount_right,
      :currency,
      :auto_accepted,
      :accepted_by,
      :accepted_at
    ])
    |> validate_required([
      :run_id,
      :strategy,
      :confidence,
      :left_type,
      :left_ids,
      :right_type,
      :right_ids,
      :auto_accepted
    ])
    |> validate_inclusion(:strategy, @valid_strategies)
    |> validate_number(:confidence,
      greater_than_or_equal_to: Decimal.new("0"),
      less_than_or_equal_to: Decimal.new("1")
    )
    |> put_auto_accepted()
    |> foreign_key_constraint(:run_id)
  end

  def accept_changeset(match, accepted_by) do
    match
    |> change(accepted_by: accepted_by, accepted_at: DateTime.utc_now())
  end

  def auto_accept_threshold, do: @auto_accept_threshold

  defp put_auto_accepted(cs) do
    confidence = get_field(cs, :confidence)

    if confidence do
      auto = Decimal.compare(confidence, @auto_accept_threshold) in [:gt, :eq]
      put_change(cs, :auto_accepted, auto)
    else
      cs
    end
  end
end
