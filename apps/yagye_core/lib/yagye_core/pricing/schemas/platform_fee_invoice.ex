defmodule YagyeCore.Pricing.Schemas.PlatformFeeInvoice do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant

  @valid_states ~w[draft issued collecting collected overdue written_off]
  @valid_collection_methods ~w[cross_net monthly_invoice direct_debit]
  @valid_modes ~w[simulation live]
  @public_id_prefix "pfi_"

  @type t :: %__MODULE__{}

  schema "platform_fee_invoices" do
    field(:public_id, :string)
    field(:mode, :string)
    field(:period_start, :date)
    field(:period_end, :date)
    field(:currency, :string)
    field(:total_amount, :integer)
    field(:collection_method, :string)
    field(:state, :string, default: "draft")
    field(:settled_against_settlement_id, :binary_id)
    field(:due_at, :utc_datetime_usec)
    field(:collected_at, :utc_datetime_usec)
    field(:collection_reference, :string)

    belongs_to(:merchant, Merchant)

    timestamps(inserted_at: :inserted_at, updated_at: :updated_at)
  end

  def create_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :period_start,
      :period_end,
      :currency,
      :total_amount,
      :collection_method,
      :settled_against_settlement_id,
      :due_at
    ])
    |> validate_required([
      :merchant_id,
      :mode,
      :period_start,
      :period_end,
      :currency,
      :total_amount,
      :collection_method
    ])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:collection_method, @valid_collection_methods)
    |> validate_length(:currency, is: 3)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint([:merchant_id, :mode, :period_start, :period_end])
    |> put_public_id()
  end

  def transition_changeset(invoice, to_state) when to_state in @valid_states do
    change(invoice, state: to_state)
  end

  defp put_public_id(%Ecto.Changeset{valid?: true} = cs) do
    put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
  end

  defp put_public_id(cs), do: cs
end
