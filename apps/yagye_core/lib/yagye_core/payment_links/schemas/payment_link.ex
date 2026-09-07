defmodule YagyeCore.PaymentLinks.Schemas.PaymentLink do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_kinds ~w[fixed_amount customer_specified invoice]
  @valid_modes ~w[simulation sandbox live]

  schema "payment_links" do
    field :public_id, :string
    field :merchant_id, Uniq.UUID
    field :mode, :string
    field :url_slug, :string
    field :kind, :string
    field :amount, :integer
    field :currency, :string
    field :description, :string
    field :image_url, :string
    field :allowed_methods, {:array, :string}, default: []
    field :collect_email, :boolean, default: false
    field :collect_phone, :boolean, default: false
    field :collect_name, :boolean, default: false
    field :reusable, :boolean, default: true
    field :max_uses, :integer
    field :use_count, :integer, default: 0
    field :active, :boolean, default: true
    field :expires_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps(inserted_at: :inserted_at)
  end

  @required ~w[merchant_id mode url_slug kind currency description]a

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :merchant_id,
      :mode,
      :url_slug,
      :kind,
      :amount,
      :currency,
      :description,
      :image_url,
      :allowed_methods,
      :collect_email,
      :collect_phone,
      :collect_name,
      :reusable,
      :max_uses,
      :use_count,
      :active,
      :expires_at,
      :metadata
    ])
    |> validate_required(@required)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_length(:currency, is: 3)
    |> validate_amount_for_kind()
    |> put_public_id()
    |> unique_constraint(:public_id)
    |> unique_constraint(:url_slug)
    |> foreign_key_constraint(:merchant_id)
  end

  defp validate_amount_for_kind(changeset) do
    kind = get_field(changeset, :kind)
    amount = get_field(changeset, :amount)

    cond do
      kind == "customer_specified" -> changeset
      is_nil(amount) -> add_error(changeset, :amount, "is required for #{kind} links")
      amount < 0 -> add_error(changeset, :amount, "must be non-negative")
      true -> changeset
    end
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, "plk_" <> Uniq.UUID.uuid7())
    end
  end
end
