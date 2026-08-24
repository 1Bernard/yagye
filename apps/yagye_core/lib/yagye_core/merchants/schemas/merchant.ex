defmodule YagyeCore.Merchants.Schemas.Merchant do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  schema "merchants" do
    field :public_id, :string
    field :legal_name, :string
    field :trading_name, :string
    field :country, :string
    field :default_currency, :string
    field :status, :string, default: "registered"
    field :onboarding_state, :string, default: "registered"
    field :kyb_tier, :integer, default: 0
    field :reviewed_by, :string
    field :approved_by, :string
    field :risk_rating, :string
    field :settlement_schedule, :map, default: %{}
    field :pricing_plan_id, Uniq.UUID
    field :activity_state, :string, default: "active"
    field :last_transaction_at, :utc_datetime_usec
    field :baseline_daily_volume, :integer
    field :quiet_since, :utc_datetime_usec
    field :api_version, :string
    field :orchestration_billing_method, :string
    field :entitlements, :map, default: %{}
    field :metadata, :map, default: %{}

    has_many :merchant_modes, YagyeCore.Merchants.Schemas.MerchantMode
    has_many :api_keys, YagyeCore.Merchants.Schemas.ApiKey

    timestamps()
  end

  @required ~w[public_id legal_name trading_name country default_currency api_version]a
  @optional ~w[
    orchestration_billing_method
    risk_rating
    pricing_plan_id
    settlement_schedule
    entitlements
    metadata
  ]a

  def changeset(merchant, attrs) do
    merchant
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:country, is: 2)
    |> validate_length(:default_currency, is: 3)
    |> unique_constraint(:public_id)
  end

  def onboarding_changeset(merchant, attrs) do
    merchant
    |> cast(attrs, [:onboarding_state, :kyb_tier, :reviewed_by, :approved_by, :status])
    |> validate_sod_actors()
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
