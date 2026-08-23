defmodule YagyeCore.Reconciliation.Schemas.ReconciliationRun do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Providers.Schemas.Provider

  @valid_kinds ~w[transaction settlement bank]
  @valid_modes ~w[simulation live]
  @valid_states ~w[created loading matching classifying completed failed]
  @public_id_prefix "rcn_"

  @type t :: %__MODULE__{}

  schema "reconciliation_runs" do
    field :public_id, :string
    field :kind, :string
    field :mode, :string
    field :scope_from, :utc_datetime_usec
    field :scope_to, :utc_datetime_usec
    field :state, :string, default: "created"
    field :left_count, :integer
    field :right_count, :integer
    field :matched_count, :integer
    field :break_count, :integer
    field :matched_value, :integer
    field :break_value, :integer
    field :currency, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :provider, Provider
    belongs_to :merchant, Merchant

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :public_id,
      :kind,
      :provider_id,
      :merchant_id,
      :mode,
      :scope_from,
      :scope_to,
      :state,
      :currency
    ])
    |> put_public_id()
    |> validate_required([:public_id, :kind, :mode, :scope_from, :scope_to])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_inclusion(:mode, @valid_modes)
    |> validate_inclusion(:state, @valid_states)
    |> validate_scope()
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:merchant_id)
    |> unique_constraint(:public_id)
  end

  def progress_changeset(%Ecto.Changeset{} = cs, counts) do
    cast(cs, counts, [
      :left_count,
      :right_count,
      :matched_count,
      :break_count,
      :matched_value,
      :break_value,
      :currency
    ])
  end

  def progress_changeset(%__MODULE__{} = run, counts) do
    cast(run, counts, [
      :left_count,
      :right_count,
      :matched_count,
      :break_count,
      :matched_value,
      :break_value,
      :currency
    ])
  end

  def transition_changeset(run, to_state) when to_state in @valid_states do
    now = DateTime.utc_now()

    changes =
      case to_state do
        "loading" -> %{state: to_state, started_at: now}
        "completed" -> %{state: to_state, completed_at: now}
        "failed" -> %{state: to_state, completed_at: now}
        _ -> %{state: to_state}
      end

    change(run, changes)
  end

  def valid_states, do: @valid_states

  defp put_public_id(%Ecto.Changeset{} = cs) do
    if get_field(cs, :public_id) do
      cs
    else
      put_change(cs, :public_id, @public_id_prefix <> Uniq.UUID.uuid7())
    end
  end

  defp validate_scope(cs) do
    from = get_field(cs, :scope_from)
    to = get_field(cs, :scope_to)

    if from && to && DateTime.compare(from, to) != :lt do
      add_error(cs, :scope_to, "must be after scope_from")
    else
      cs
    end
  end
end
