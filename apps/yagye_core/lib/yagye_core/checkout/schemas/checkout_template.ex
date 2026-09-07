defmodule YagyeCore.Checkout.Schemas.CheckoutTemplate do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Checkout.Schemas.CheckoutTemplateComponent

  @valid_statuses ~w[draft published archived]
  @valid_modes ~w[simulation sandbox live]

  schema "checkout_templates" do
    field :public_id, :string
    field :merchant_id, Uniq.UUID
    field :mode, :string
    field :name, :string
    field :status, :string, default: "draft"
    field :theme, :map, default: %{}

    has_many :components, CheckoutTemplateComponent, foreign_key: :template_id

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[merchant_id mode name]a

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:merchant_id, :mode, :name, :status, :theme])
    |> validate_required(@required)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:status, @valid_statuses)
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint([:merchant_id, :mode],
      name: :checkout_templates_one_published_per_merchant_mode,
      message: "a published template already exists for this merchant and mode"
    )
    |> foreign_key_constraint(:merchant_id)
  end

  def publish_changeset(template) do
    changeset(template, %{status: "published"})
  end

  def archive_changeset(template) do
    changeset(template, %{status: "archived"})
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, "ckt_" <> Uniq.UUID.uuid7())
    end
  end
end
