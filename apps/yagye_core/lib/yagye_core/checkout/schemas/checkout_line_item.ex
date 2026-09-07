defmodule YagyeCore.Checkout.Schemas.CheckoutLineItem do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_kinds ~w[item shipping tax discount]

  schema "checkout_line_items" do
    field :session_id, Uniq.UUID
    field :position, :integer
    field :kind, :string
    field :description, :string
    field :quantity, :integer, default: 1
    field :unit_amount, :integer
    field :total_amount, :integer
    field :image_url, :string

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[session_id position kind description quantity unit_amount total_amount]a

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :session_id,
      :position,
      :kind,
      :description,
      :quantity,
      :unit_amount,
      :total_amount,
      :image_url
    ])
    |> validate_required(@required)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_discount_sign()
    |> foreign_key_constraint(:session_id)
    |> unique_constraint([:session_id, :position])
  end

  defp validate_discount_sign(changeset) do
    kind = get_field(changeset, :kind)
    unit_amount = get_field(changeset, :unit_amount)

    if kind == "discount" && unit_amount && unit_amount >= 0 do
      add_error(changeset, :unit_amount, "must be negative for discount line items")
    else
      changeset
    end
  end
end
