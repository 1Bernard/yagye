defmodule YagyeCore.Invoices.Schemas.InvoiceLineItem do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "invoice_line_items" do
    field :invoice_id, Uniq.UUID
    field :position, :integer
    field :description, :string
    field :quantity, :decimal
    field :unit_amount, :integer
    field :tax_rate_bps, :integer
    field :total_amount, :integer

    timestamps(updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :invoice_id,
      :position,
      :description,
      :quantity,
      :unit_amount,
      :tax_rate_bps,
      :total_amount
    ])
    |> validate_required([
      :invoice_id,
      :position,
      :description,
      :quantity,
      :unit_amount,
      :tax_rate_bps,
      :total_amount
    ])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:tax_rate_bps, greater_than_or_equal_to: 0)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> unique_constraint([:invoice_id, :position])
    |> foreign_key_constraint(:invoice_id)
  end
end
