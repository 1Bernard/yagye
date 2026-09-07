defmodule YagyeCore.Payments.Schemas.PaymentBankTransferDetails do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:payment_id, Uniq.UUID, autogenerate: false}
  @foreign_key_type Uniq.UUID

  schema "payment_bank_transfer_details" do
    field :virtual_account_number, :string
    field :bank_code, :string
    field :expected_by, :utc_datetime_usec
    field :received_at, :utc_datetime_usec
  end

  @required ~w[payment_id]a

  def changeset(details, attrs) do
    details
    |> cast(attrs, [:payment_id, :virtual_account_number, :bank_code, :expected_by, :received_at])
    |> validate_required(@required)
    |> foreign_key_constraint(:payment_id)
  end
end
