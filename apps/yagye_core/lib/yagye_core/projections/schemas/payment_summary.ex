defmodule YagyeCore.Projections.Schemas.PaymentSummary do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # payment_id is the PK — one row per payment
  @primary_key {:payment_id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "proj_payment_summaries" do
    field :merchant_id, Ecto.UUID
    field :mode, :string
    field :aggregate_version, :integer
    field :state, :string
    field :method, :string
    field :provider_code, :string
    field :amount, :integer
    field :currency, :string
    field :net_amount, :integer
    field :platform_fee, :integer
    field :provider_fee, :integer
    field :settlement_id, Ecto.UUID
    field :settlement_state, :string
    field :customer_reference, :string
    field :merchant_reference, :string
    field :created_at, :utc_datetime_usec
    field :last_transition_at, :utc_datetime_usec
    field :last_event_id, :string
  end

  def upsert_changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :payment_id,
      :merchant_id,
      :mode,
      :aggregate_version,
      :state,
      :method,
      :provider_code,
      :amount,
      :currency,
      :net_amount,
      :platform_fee,
      :provider_fee,
      :settlement_id,
      :settlement_state,
      :customer_reference,
      :merchant_reference,
      :created_at,
      :last_transition_at,
      :last_event_id
    ])
    |> validate_required([
      :payment_id,
      :merchant_id,
      :mode,
      :aggregate_version,
      :state,
      :method,
      :amount,
      :currency,
      :created_at,
      :last_transition_at,
      :last_event_id
    ])
  end
end
