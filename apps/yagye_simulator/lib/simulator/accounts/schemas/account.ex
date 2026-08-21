defmodule Simulator.Accounts.Schemas.Account do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Scenarios.Schemas.Scenario

  schema "gw_accounts" do
    field :account_ref, :string
    field :display_name, :string
    field :webhook_url, :string
    field :webhook_secret, :string
    field :webhook_signing_algorithm, :string, default: "HS256"
    field :settlement_cadence, :string, default: "daily"
    field :settlement_cutoff_time, :time
    field :settlement_timezone, :string, default: "Africa/Accra"
    field :currency, :string
    field :fee_percentage_bps, :integer, default: 150
    field :fee_fixed_minor, :integer, default: 0

    belongs_to :default_scenario, Scenario

    # Suppress auto timestamps — schema uses created_at only
    field :created_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :account_ref,
      :display_name,
      :webhook_url,
      :webhook_secret,
      :webhook_signing_algorithm,
      :settlement_cadence,
      :settlement_cutoff_time,
      :settlement_timezone,
      :currency,
      :fee_percentage_bps,
      :fee_fixed_minor,
      :default_scenario_id
    ])
    |> validate_required([:account_ref, :display_name, :webhook_url, :webhook_secret, :currency])
    |> validate_inclusion(:webhook_signing_algorithm, ~w[HS256 HS512 SHA256])
    |> validate_inclusion(:settlement_cadence, ~w[daily t_plus_2 weekly])
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:account_ref)
    |> foreign_key_constraint(:default_scenario_id)
  end
end
