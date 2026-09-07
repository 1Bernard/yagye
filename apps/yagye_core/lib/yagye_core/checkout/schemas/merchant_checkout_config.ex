defmodule YagyeCore.Checkout.Schemas.MerchantCheckoutConfig do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:merchant_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  schema "merchant_checkout_configs" do
    field :display_name, :string
    field :logo_url, :string
    field :brand_colour, :string
    field :support_email, :string
    field :support_phone, :string
    field :website_url, :string
    field :terms_url, :string
    field :privacy_url, :string
    field :refund_policy_url, :string
    field :default_locale, :string, default: "en"
    field :updated_at, :utc_datetime_usec
  end

  @required ~w[merchant_id display_name default_locale]a

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :merchant_id,
      :display_name,
      :logo_url,
      :brand_colour,
      :support_email,
      :support_phone,
      :website_url,
      :terms_url,
      :privacy_url,
      :refund_policy_url,
      :default_locale
    ])
    |> validate_required(@required)
    |> validate_format(:brand_colour, ~r/\A#[0-9A-Fa-f]{6}\z/,
      message: "must be a valid hex colour e.g. #3D47F5"
    )
    |> put_updated_at()
    |> foreign_key_constraint(:merchant_id)
  end

  defp put_updated_at(changeset) do
    put_change(changeset, :updated_at, DateTime.utc_now(:microsecond))
  end
end
