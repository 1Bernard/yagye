defmodule YagyeCore.Disputes.Schemas.Refund do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Disputes.Schemas.Dispute
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment

  @valid_reasons ~w[duplicate fraudulent customer_request dispute_retracted]
  @valid_states ~w[requested succeeded failed]

  schema "refunds" do
    field :public_id, :string
    field :amount, :integer
    field :currency, :string
    field :reason, :string
    field :state, :string, default: "requested"
    field :failure_reason, :string
    field :metadata, :map, default: %{}

    belongs_to :payment, Payment
    belongs_to :merchant, Merchant
    belongs_to :dispute, Dispute

    timestamps()
  end

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, [
      :payment_id,
      :merchant_id,
      :dispute_id,
      :amount,
      :currency,
      :reason,
      :metadata
    ])
    |> validate_required([:payment_id, :merchant_id, :amount, :currency, :reason])
    |> validate_inclusion(:reason, @valid_reasons)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:dispute_id)
    |> unique_constraint(:public_id)
  end

  def settle_changeset(refund) do
    change(refund, state: "succeeded")
  end

  def fail_changeset(refund, reason) do
    change(refund, state: "failed", failure_reason: reason)
  end

  def valid_states, do: @valid_states

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "ref_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset
end
