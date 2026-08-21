defmodule Simulator.Scenarios.Schemas.Scenario do
  @moduledoc false

  use Simulator.Schema
  import Ecto.Changeset

  schema "gw_scenarios" do
    field :name, :string
    field :active, :boolean, default: true
    field :is_default, :boolean, default: false
    field :seed, :integer
    field :latency_p50_ms, :integer
    field :latency_p95_ms, :integer
    field :latency_p99_ms, :integer
    field :success_rate, :decimal
    field :decline_rate, :decimal
    field :provider_error_rate, :decimal
    field :timeout_rate, :decimal
    field :timeout_creates_charge, :boolean
    field :duplicate_webhook_rate, :decimal
    field :out_of_order_rate, :decimal
    field :webhook_drop_rate, :decimal
    field :webhook_delay_max_ms, :integer
    field :three_ds_required_rate, :decimal
    field :auth_validity_hours, :integer
    field :supports_partial_capture, :boolean
    field :supports_multiple_capture, :boolean
    field :supports_incremental_auth, :boolean
    field :supports_void, :boolean
    field :arn_issued_at, :string
    field :settlement_discrepancy_rate, :decimal
    field :settlement_missing_line_rate, :decimal
    field :fee_drift_bps, :integer

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  @required ~w[name latency_p50_ms latency_p95_ms latency_p99_ms success_rate
               decline_rate provider_error_rate timeout_rate timeout_creates_charge
               auth_validity_hours arn_issued_at fee_drift_bps]a

  @optional ~w[active is_default seed duplicate_webhook_rate out_of_order_rate
               webhook_drop_rate webhook_delay_max_ms three_ds_required_rate
               supports_partial_capture supports_multiple_capture supports_incremental_auth
               supports_void settlement_discrepancy_rate settlement_missing_line_rate]a

  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:arn_issued_at, ~w[authorisation capture settlement])
    |> validate_rates()
    |> unique_constraint(:name)
  end

  defp validate_rates(changeset) do
    changeset
    |> validate_number(:success_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:decline_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:provider_error_rate,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
    |> validate_number(:timeout_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
