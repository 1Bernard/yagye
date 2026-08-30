defmodule YagyeCore.Invoices.Schemas.InvoiceDelivery do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_channels ~w[email whatsapp sms link_copied]
  @valid_states ~w[queued sent delivered opened failed]

  schema "invoice_deliveries" do
    field :invoice_id, Uniq.UUID
    field :channel, :string
    field :destination_hash, :string
    field :state, :string, default: "queued"
    field :provider_reference, :string
    field :sent_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :opened_at, :utc_datetime_usec
    field :failure_reason, :string

    timestamps(updated_at: false)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :invoice_id,
      :channel,
      :destination_hash,
      :state,
      :provider_reference,
      :sent_at,
      :delivered_at,
      :opened_at,
      :failure_reason
    ])
    |> validate_required([:invoice_id, :channel, :destination_hash])
    |> validate_inclusion(:channel, @valid_channels)
    |> validate_inclusion(:state, @valid_states)
    |> foreign_key_constraint(:invoice_id)
  end
end
