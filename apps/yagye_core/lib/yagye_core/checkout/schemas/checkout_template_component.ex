defmodule YagyeCore.Checkout.Schemas.CheckoutTemplateComponent do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_component_types ~w[order_summary payment_methods customer_fields
                            coupon_input trust_badges submit_button]

  schema "checkout_template_components" do
    field :template_id, Uniq.UUID
    field :component_type, :string
    field :position, :integer
    field :visible, :boolean, default: true
    field :config, :map, default: %{}

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[template_id component_type position]a

  def changeset(component, attrs) do
    component
    |> cast(attrs, [:template_id, :component_type, :position, :visible, :config])
    |> validate_required(@required)
    |> validate_inclusion(:component_type, @valid_component_types)
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:template_id)
    |> unique_constraint([:template_id, :position])
  end
end
