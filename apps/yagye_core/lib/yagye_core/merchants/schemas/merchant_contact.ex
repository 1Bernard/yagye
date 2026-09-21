defmodule YagyeCore.Merchants.Schemas.MerchantContact do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "merchant_contacts" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    field :general_email, :string
    field :support_email, :string
    field :disputes_email, :string
    field :phone_number, :string
    field :whatsapp_number, :string
    field :whatsapp_label, :string
    field :website_url, :string
    field :twitter_handle, :string
    field :facebook_username, :string
    field :instagram_handle, :string

    timestamps()
  end

  @optional ~w[
    general_email support_email disputes_email phone_number
    whatsapp_number whatsapp_label website_url
    twitter_handle facebook_username instagram_handle
  ]a

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:merchant_id | @optional])
    |> validate_required([:merchant_id])
    |> validate_format(:general_email, ~r/\A[^@\s]+@[^@\s]+\z/)
    |> validate_format(:support_email, ~r/\A[^@\s]+@[^@\s]+\z/)
    |> validate_format(:disputes_email, ~r/\A[^@\s]+@[^@\s]+\z/)
    |> unique_constraint(:merchant_id)
    |> foreign_key_constraint(:merchant_id)
  end
end
