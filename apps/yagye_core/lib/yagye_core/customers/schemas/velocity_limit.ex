defmodule YagyeCore.Customers.Schemas.VelocityLimit do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  @valid_entity_types ~w[merchant customer]

  @type t :: %__MODULE__{}

  schema "velocity_limits" do
    field(:entity_type, :string)
    field(:risk_tier, :string)
    field(:payment_method, :string)
    field(:currency, :string)
    field(:max_single_txn, :integer)
    field(:max_daily, :integer)
    field(:max_monthly, :integer)

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end

  def create_changeset(limit, attrs) do
    limit
    |> cast(attrs, [
      :entity_type,
      :risk_tier,
      :payment_method,
      :currency,
      :max_single_txn,
      :max_daily,
      :max_monthly
    ])
    |> validate_required([:entity_type, :risk_tier, :payment_method, :currency])
    |> validate_inclusion(:entity_type, @valid_entity_types)
    |> validate_length(:currency, is: 3)
    |> unique_constraint([:entity_type, :risk_tier, :payment_method, :currency])
  end

  # Default limits used as fallback when no DB row is found.
  # Amounts in minor units (GHS pesewas: 100 pesewas = 1 GHS).
  # BoG MoMo tier values are approximate — seed the DB with authoritative values
  # before going live.
  def default_limits do
    [
      # Merchant limits — any payment method
      %{
        entity_type: "merchant",
        risk_tier: "low",
        payment_method: "any",
        currency: "GHS",
        max_single_txn: 5_000_000,
        max_daily: 50_000_000,
        max_monthly: 500_000_000
      },
      %{
        entity_type: "merchant",
        risk_tier: "medium",
        payment_method: "any",
        currency: "GHS",
        max_single_txn: 1_000_000,
        max_daily: 10_000_000,
        max_monthly: 100_000_000
      },
      %{
        entity_type: "merchant",
        risk_tier: "high",
        payment_method: "any",
        currency: "GHS",
        max_single_txn: 200_000,
        max_daily: 2_000_000,
        max_monthly: 20_000_000
      },
      # Customer limits — mobile money (BoG regulated)
      %{
        entity_type: "customer",
        risk_tier: "tier_1",
        payment_method: "mobile_money",
        currency: "GHS",
        max_single_txn: 10_000,
        max_daily: 10_000,
        max_monthly: 100_000
      },
      %{
        entity_type: "customer",
        risk_tier: "tier_2",
        payment_method: "mobile_money",
        currency: "GHS",
        max_single_txn: 30_000,
        max_daily: 100_000,
        max_monthly: 500_000
      },
      %{
        entity_type: "customer",
        risk_tier: "tier_3",
        payment_method: "mobile_money",
        currency: "GHS",
        max_single_txn: 1_000_000,
        max_daily: 5_000_000,
        max_monthly: 5_000_000
      },
      # Customer limits — card
      %{
        entity_type: "customer",
        risk_tier: "tier_1",
        payment_method: "card",
        currency: "GHS",
        max_single_txn: 100_000,
        max_daily: 500_000,
        max_monthly: 2_000_000
      },
      %{
        entity_type: "customer",
        risk_tier: "tier_2",
        payment_method: "card",
        currency: "GHS",
        max_single_txn: 500_000,
        max_daily: 2_000_000,
        max_monthly: 10_000_000
      },
      %{
        entity_type: "customer",
        risk_tier: "tier_3",
        payment_method: "card",
        currency: "GHS",
        max_single_txn: 2_000_000,
        max_daily: 10_000_000,
        max_monthly: 50_000_000
      }
    ]
  end
end
