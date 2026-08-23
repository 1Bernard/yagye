defmodule YagyeCore.Reconciliation.Schemas.ReconciliationBreak do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Reconciliation.Schemas.ReconciliationRun

  # Closed taxonomy — `unknown` is NEVER terminal; must be triaged to something specific.
  @valid_classifications ~w[
    missing_on_left
    missing_on_right
    amount_mismatch
    duplicate_on_left
    duplicate_on_right
    timing_difference
    fee_discrepancy
    currency_mismatch
    unknown
  ]
  @valid_severities ~w[critical high medium low]
  @valid_states ~w[detected triaged assigned investigating resolved escalated written_off]
  @valid_modes ~w[simulation live]
  @public_id_prefix "brk_"

  # SLA hours by severity
  @sla_hours %{"critical" => 24, "high" => 72, "medium" => 168, "low" => 336}

  @type t :: %__MODULE__{}

  schema "reconciliation_breaks" do
    field :public_id, :string
    field :mode, :string
    field :classification, :string
    field :severity, :string
    field :state, :string, default: "detected"
    field :left_ref, :string
    field :right_ref, :string
    field :expected_amount, :integer
    field :actual_amount, :integer
    field :difference, :integer
    field :currency, :string
    field :evidence, :map, default: %{}
    field :assigned_to, :string
    field :resolution_code, :string
    field :resolution_note, :string
    field :resolving_entry_id, Uniq.UUID
    field :detected_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :sla_due_at, :utc_datetime_usec

    belongs_to :run, ReconciliationRun
    belongs_to :merchant, Merchant
    belongs_to :provider, Provider
  end

  def changeset(break, attrs) do
    break
    |> cast(attrs, [
      :public_id,
      :run_id,
      :merchant_id,
      :provider_id,
      :mode,
      :classification,
      :severity,
      :state,
      :left_ref,
      :right_ref,
      :expected_amount,
      :actual_amount,
      :difference,
      :currency,
      :evidence,
      :detected_at
    ])
    |> put_public_id()
    |> put_detected_at()
    |> put_sla_due_at()
    |> validate_required([
      :public_id,
      :run_id,
      :mode,
      :classification,
      :severity,
      :state,
      :detected_at
    ])
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:classification, @valid_classifications)
    |> validate_inclusion(:severity, @valid_severities)
    |> validate_inclusion(:state, @valid_states)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint(:public_id)
  end

  def transition_changeset(break, to_state) when to_state in @valid_states do
    changes = %{state: to_state}

    changes =
      if to_state in ["resolved", "written_off"],
        do: Map.put(changes, :resolved_at, DateTime.utc_now()),
        else: changes

    change(break, changes)
  end

  def assign_changeset(break, user) do
    change(break, state: "assigned", assigned_to: user)
  end

  def resolve_changeset(break, entry_id, resolution_code, resolution_note) do
    change(break,
      state: "resolved",
      resolving_entry_id: entry_id,
      resolution_code: resolution_code,
      resolution_note: resolution_note,
      resolved_at: DateTime.utc_now()
    )
  end

  def valid_states, do: @valid_states
  def valid_classifications, do: @valid_classifications
  def sla_hours, do: @sla_hours

  defp put_public_id(cs) do
    if get_field(cs, :public_id) do
      cs
    else
      put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
    end
  end

  defp put_detected_at(cs) do
    if get_field(cs, :detected_at) do
      cs
    else
      put_change(cs, :detected_at, DateTime.utc_now())
    end
  end

  defp put_sla_due_at(cs) do
    severity = get_field(cs, :severity)
    detected_at = get_field(cs, :detected_at)

    if severity && detected_at do
      hours = Map.get(@sla_hours, severity, 168)
      sla = DateTime.add(detected_at, hours * 3600, :second)
      put_change(cs, :sla_due_at, sla)
    else
      cs
    end
  end
end
