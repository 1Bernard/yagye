defmodule YagyeCore.Reconciliation.Schemas.AdjustmentApproval do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Reconciliation.Schemas.ReconciliationBreak

  @type t :: %__MODULE__{}

  schema "adjustment_approvals" do
    field :proposed_by, :string
    field :proposed_at, :utc_datetime_usec
    field :proposed_action, :map
    field :approved_by, :string
    field :approved_at, :utc_datetime_usec
    field :rejected_reason, :string

    belongs_to :break, ReconciliationBreak

    timestamps(updated_at: false)
  end

  def propose_changeset(approval, attrs) do
    approval
    |> cast(attrs, [:break_id, :proposed_by, :proposed_at, :proposed_action])
    |> put_proposed_at()
    |> validate_required([:break_id, :proposed_by, :proposed_at, :proposed_action])
    |> foreign_key_constraint(:break_id)
  end

  def approve_changeset(approval, approved_by) do
    approval
    |> cast(%{approved_by: approved_by, approved_at: DateTime.utc_now()}, [
      :approved_by,
      :approved_at
    ])
    |> validate_required([:approved_by])
    |> validate_sod()
  end

  def reject_changeset(approval, reason) do
    approval
    |> cast(%{rejected_reason: reason}, [:rejected_reason])
    |> validate_required([:rejected_reason])
  end

  defp put_proposed_at(cs) do
    if get_field(cs, :proposed_at) do
      cs
    else
      put_change(cs, :proposed_at, DateTime.utc_now())
    end
  end

  defp validate_sod(cs) do
    proposed_by = get_field(cs, :proposed_by)
    approved_by = get_change(cs, :approved_by)

    if approved_by && approved_by == proposed_by do
      add_error(cs, :approved_by, "cannot be the same as the proposer (SoD violation)")
    else
      cs
    end
  end
end
