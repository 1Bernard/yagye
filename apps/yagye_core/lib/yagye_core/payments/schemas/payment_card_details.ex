defmodule YagyeCore.Payments.Schemas.PaymentCardDetails do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:payment_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  @valid_funding ~w[credit debit prepaid]
  @valid_card_categories ~w[consumer commercial]
  @valid_initiated_by ~w[cit mit]
  @valid_stored_credentials ~w[initial subsequent]
  @valid_mit_types ~w[recurring unscheduled instalment]

  schema "payment_card_details" do
    field :brand, :string
    field :last4, :string
    field :bin, :string
    field :funding, :string
    field :card_category, :string
    field :issuer_name, :string
    field :issuer_country, :string
    field :exp_month, :integer
    field :exp_year, :integer
    field :provider_token, :string
    field :network_token_used, :boolean
    field :cardholder_name_subject_ref, Uniq.UUID
    field :avs_result, :string
    field :cvv_result, :string
    field :auth_code, :string
    field :rrn, :string
    field :arn, :string
    field :network_transaction_id, :string
    field :initiated_by, :string
    field :stored_credential, :string
    field :mit_type, :string
  end

  @required ~w[payment_id]a

  def changeset(details, attrs) do
    details
    |> cast(attrs, [
      :payment_id,
      :brand,
      :last4,
      :bin,
      :funding,
      :card_category,
      :issuer_name,
      :issuer_country,
      :exp_month,
      :exp_year,
      :provider_token,
      :network_token_used,
      :cardholder_name_subject_ref,
      :avs_result,
      :cvv_result,
      :auth_code,
      :rrn,
      :arn,
      :network_transaction_id,
      :initiated_by,
      :stored_credential,
      :mit_type
    ])
    |> validate_required(@required)
    |> validate_inclusion(:funding, @valid_funding, allow_nil: true)
    |> validate_inclusion(:card_category, @valid_card_categories, allow_nil: true)
    |> validate_inclusion(:initiated_by, @valid_initiated_by, allow_nil: true)
    |> validate_inclusion(:stored_credential, @valid_stored_credentials, allow_nil: true)
    |> validate_inclusion(:mit_type, @valid_mit_types, allow_nil: true)
    |> foreign_key_constraint(:payment_id)
  end
end
