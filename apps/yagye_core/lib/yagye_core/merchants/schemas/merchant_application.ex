defmodule YagyeCore.Merchants.Schemas.MerchantApplication do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "merchant_applications" do
    field :public_id, :string
    field :status, :string, default: "submitted"

    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :phone_number, :string
    field :job_title, :string

    field :legal_name, :string
    field :trading_name, :string
    field :country, :string
    field :default_currency, :string
    field :industry, :string
    field :employee_range, :string
    field :annual_tpv_estimate_cents, :integer
    field :website_url, :string
    field :use_case, :string
    field :expected_methods, {:array, :string}, default: []

    field :reviewed_by, :string
    field :review_notes, :string
    field :reviewed_at, :utc_datetime_usec

    field :approved_by, :string
    field :rejected_reason, :string

    belongs_to :merchant, YagyeCore.Merchants.Schemas.Merchant

    timestamps()
  end

  @required ~w[public_id first_name last_name email legal_name trading_name country default_currency]a
  @optional ~w[
    status phone_number job_title industry employee_range annual_tpv_estimate_cents
    website_url use_case expected_methods reviewed_by review_notes reviewed_at
    approved_by rejected_reason merchant_id
  ]a

  def changeset(application, attrs) do
    application
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:country, is: 2)
    |> validate_length(:default_currency, is: 3)
    |> validate_format(:email, ~r/\A[^@\s]+@[^@\s]+\z/)
    |> validate_inclusion(:status, ~w[submitted under_review approved rejected])
    |> unique_constraint(:public_id)
  end

  def review_changeset(application, attrs) do
    application
    |> cast(attrs, [:status, :reviewed_by, :review_notes, :reviewed_at])
    |> validate_required([:reviewed_by])
  end

  def approve_changeset(application, attrs) do
    application
    |> cast(attrs, [:status, :approved_by, :merchant_id])
    |> validate_required([:approved_by])
    |> validate_sod_actors()
  end

  def reject_changeset(application, attrs) do
    application
    |> cast(attrs, [:status, :rejected_reason])
    |> validate_required([:rejected_reason])
  end

  defp validate_sod_actors(changeset) do
    approved_by = get_field(changeset, :approved_by)
    reviewed_by = get_field(changeset, :reviewed_by)

    if approved_by != nil and approved_by == reviewed_by do
      add_error(changeset, :approved_by, "must differ from reviewed_by")
    else
      changeset
    end
  end
end
