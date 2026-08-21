defmodule YagyeCore.Disputes.Schemas.Dispute do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment

  @valid_stages ~w[opened evidence_required under_review resolved]
  @valid_outcomes ~w[won lost retracted]
  @valid_reasons ~w[duplicate fraud credit_not_processed product_not_received subscription_cancelled]

  schema "disputes" do
    field :public_id, :string
    field :network, :string
    field :reason, :string
    field :amount, :integer
    field :currency, :string
    field :stage, :string, default: "opened"
    field :outcome, :string
    field :evidence_due_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :payment, Payment
    belongs_to :merchant, Merchant

    timestamps()
  end

  def changeset(dispute, attrs) do
    dispute
    |> cast(attrs, [
      :payment_id,
      :merchant_id,
      :network,
      :reason,
      :amount,
      :currency,
      :evidence_due_at,
      :metadata
    ])
    |> validate_required([:payment_id, :merchant_id, :network, :reason, :amount, :currency])
    |> validate_inclusion(:reason, @valid_reasons)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint(:public_id)
  end

  def resolve_changeset(dispute, outcome) when outcome in @valid_outcomes do
    change(dispute, stage: "resolved", outcome: outcome, resolved_at: DateTime.utc_now())
  end

  def advance_stage_changeset(dispute, stage) when stage in @valid_stages do
    change(dispute, stage: stage)
  end

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "dsp_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset
end
