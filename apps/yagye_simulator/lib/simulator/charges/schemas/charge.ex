defmodule Simulator.Charges.Schemas.Charge do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Scenarios.Schemas.Scenario

  @valid_states ~w[PENDING_AUTH AUTHORISED CAPTURED PARTIALLY_CAPTURED VOIDED DECLINED REVERSED AUTH_EXPIRED]
  @valid_instruments ~w[CARD WALLET BANK]

  schema "gw_charges" do
    field :charge_ref, :string
    field :idempotency_key, :string
    field :amount_minor, :integer
    field :currency, :string
    field :instrument_type, :string
    field :state, :string, default: "PENDING_AUTH"
    field :authorised_amount_minor, :integer
    field :captured_amount_minor, :integer, default: 0
    field :auth_expires_at, :utc_datetime_usec
    field :authorised_at, :utc_datetime_usec
    field :voided_at, :utc_datetime_usec
    field :decline_code, :string
    field :auth_code, :string
    field :rrn, :string
    field :arn, :string
    field :seed, :integer

    belongs_to :account, Account
    belongs_to :scenario, Scenario

    field :created_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
    field :updated_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(charge, attrs) do
    charge
    |> cast(attrs, [
      :account_id,
      :charge_ref,
      :idempotency_key,
      :amount_minor,
      :currency,
      :instrument_type,
      :state,
      :authorised_amount_minor,
      :captured_amount_minor,
      :auth_expires_at,
      :authorised_at,
      :decline_code,
      :auth_code,
      :rrn,
      :arn,
      :scenario_id,
      :seed
    ])
    |> validate_required([:account_id, :charge_ref, :amount_minor, :currency, :instrument_type])
    |> validate_inclusion(:state, @valid_states)
    |> validate_inclusion(:instrument_type, @valid_instruments)
    |> validate_number(:amount_minor, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:charge_ref)
    |> unique_constraint([:account_id, :idempotency_key])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:scenario_id)
  end

  def transition_changeset(charge, to_state, extra \\ %{}) do
    charge
    |> cast(Map.merge(%{state: to_state, updated_at: DateTime.utc_now()}, extra), [
      :state,
      :updated_at,
      :authorised_at,
      :authorised_amount_minor,
      :captured_amount_minor,
      :auth_code,
      :rrn,
      :arn,
      :decline_code,
      :voided_at
    ])
    |> validate_inclusion(:state, @valid_states)
  end
end
