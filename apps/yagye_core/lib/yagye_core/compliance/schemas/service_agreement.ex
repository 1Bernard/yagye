defmodule YagyeCore.Compliance.Schemas.ServiceAgreement do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "service_agreements" do
    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    field :agreement_version, :string
    field :accepted_at, :utc_datetime_usec
    field :signatory_name, :string
    field :signatory_email, :string
    field :signatory_phone, :string
    field :signatory_job_title, :string
    field :ip_address, :string
    field :user_agent, :string

    timestamps(updated_at: false)
  end

  @required ~w[merchant_id agreement_version accepted_at signatory_name signatory_email]a
  @optional ~w[signatory_phone signatory_job_title ip_address user_agent]a

  def changeset(agreement, attrs) do
    agreement
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_format(:signatory_email, ~r/\A[^@\s]+@[^@\s]+\z/)
    |> foreign_key_constraint(:merchant_id)
  end
end
