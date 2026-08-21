defmodule Simulator.Refunds.Schemas.Refund do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account
  alias Simulator.Charges.Schemas.Charge

  @valid_states ~w[REQUESTED OK PARTIAL FAILED]

  schema "gw_refunds" do
    field :refund_ref, :string
    field :amount_minor, :integer
    field :currency, :string
    field :state, :string, default: "REQUESTED"
    field :refund_arn, :string
    field :fee_minor, :integer, default: 0
    field :failure_code, :string
    field :injected_defect, :string

    belongs_to :charge, Charge
    belongs_to :account, Account

    field :created_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
    field :updated_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, [
      :charge_id,
      :account_id,
      :refund_ref,
      :amount_minor,
      :currency,
      :state,
      :fee_minor,
      :failure_code,
      :injected_defect
    ])
    |> validate_required([:charge_id, :account_id, :refund_ref, :amount_minor, :currency])
    |> validate_inclusion(:state, @valid_states)
    |> validate_number(:amount_minor, greater_than: 0)
    |> validate_number(:fee_minor, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:refund_ref)
    |> foreign_key_constraint(:charge_id)
    |> foreign_key_constraint(:account_id)
  end

  def complete_changeset(refund, attrs) do
    refund
    |> cast(attrs, [:state, :refund_arn, :fee_minor, :failure_code, :updated_at])
    |> validate_inclusion(:state, @valid_states)
  end
end
