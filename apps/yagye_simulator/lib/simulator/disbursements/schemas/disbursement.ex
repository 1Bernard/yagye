defmodule Simulator.Disbursements.Schemas.Disbursement do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  alias Simulator.Accounts.Schemas.Account

  @valid_states ~w[SUBMITTED PAID RETURNED FAILED]

  schema "gw_disbursements" do
    field :disbursement_ref, :string
    field :amount_minor, :integer
    field :currency, :string
    field :destination_type, :string
    field :destination_ref, :string
    field :state, :string, default: "SUBMITTED"
    field :failure_code, :string
    field :return_reason, :string
    field :paid_at, :utc_datetime_usec
    field :returned_at, :utc_datetime_usec
    field :confirmation_delay_ms, :integer, default: 5_000
    field :injected_defect, :string

    belongs_to :account, Account

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  def changeset(disbursement, attrs) do
    disbursement
    |> cast(attrs, [
      :account_id,
      :disbursement_ref,
      :amount_minor,
      :currency,
      :destination_type,
      :destination_ref,
      :state,
      :failure_code,
      :return_reason,
      :paid_at,
      :returned_at,
      :confirmation_delay_ms,
      :injected_defect
    ])
    |> validate_required([
      :account_id,
      :disbursement_ref,
      :amount_minor,
      :currency,
      :destination_type,
      :destination_ref,
      :state
    ])
    |> validate_inclusion(:state, @valid_states)
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:disbursement_ref)
    |> foreign_key_constraint(:account_id)
  end
end
