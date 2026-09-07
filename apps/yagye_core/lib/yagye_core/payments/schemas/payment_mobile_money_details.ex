defmodule YagyeCore.Payments.Schemas.PaymentMobileMoneyDetails do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:payment_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  @valid_networks ~w[mtn telecel airteltigo]
  @valid_network_sources ~w[user_selected lookup prefix_guess]
  @valid_charge_bearers ~w[merchant customer]

  schema "payment_mobile_money_details" do
    field :network, :string
    field :network_source, :string
    field :msisdn_subject_ref, Uniq.UUID
    field :msisdn_masked, :string
    field :msisdn_hash, :string
    field :account_name_returned, :string
    field :name_match_score, :decimal
    field :charge_bearer, :string
    field :levy_amount, :integer
    field :prompt_sent_at, :utc_datetime_usec
    field :prompt_expires_at, :utc_datetime_usec
    field :approved_at, :utc_datetime_usec
    field :network_reference, :string
    field :financial_transaction_id, :string
  end

  @required ~w[payment_id network network_source msisdn_masked msisdn_hash charge_bearer]a

  def changeset(details, attrs) do
    details
    |> cast(attrs, [
      :payment_id,
      :network,
      :network_source,
      :msisdn_subject_ref,
      :msisdn_masked,
      :msisdn_hash,
      :account_name_returned,
      :name_match_score,
      :charge_bearer,
      :levy_amount,
      :prompt_sent_at,
      :prompt_expires_at,
      :approved_at,
      :network_reference,
      :financial_transaction_id
    ])
    |> validate_required(@required)
    |> validate_inclusion(:network, @valid_networks)
    |> validate_inclusion(:network_source, @valid_network_sources)
    |> validate_inclusion(:charge_bearer, @valid_charge_bearers)
    |> foreign_key_constraint(:payment_id)
  end
end
