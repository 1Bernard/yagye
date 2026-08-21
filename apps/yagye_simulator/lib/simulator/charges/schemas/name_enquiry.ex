defmodule Simulator.Charges.Schemas.NameEnquiry do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Charges.Schemas.Charge

  @valid_networks ~w[MTN TELECEL AIRTELTIGO]
  @valid_outcomes ~w[FOUND NOT_FOUND TIMEOUT NETWORK_ERROR]

  schema "gw_name_enquiries" do
    field :network, :string
    field :msisdn, :string
    field :outcome, :string
    field :account_name, :string
    field :delay_ms, :integer, default: 200
    field :queried_at, :utc_datetime_usec

    belongs_to :account, Account
    belongs_to :charge, Charge
  end

  def changeset(enquiry, attrs) do
    enquiry
    |> cast(attrs, [
      :account_id,
      :charge_id,
      :network,
      :msisdn,
      :outcome,
      :account_name,
      :delay_ms,
      :queried_at
    ])
    |> validate_required([:account_id, :network, :msisdn, :outcome, :queried_at])
    |> validate_inclusion(:network, @valid_networks)
    |> validate_inclusion(:outcome, @valid_outcomes)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:charge_id)
  end
end
