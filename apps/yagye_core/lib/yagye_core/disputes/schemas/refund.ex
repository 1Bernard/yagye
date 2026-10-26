defmodule YagyeCore.Disputes.Schemas.Refund do
  @moduledoc false

  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  alias YagyeCore.Disputes.Schemas.Dispute
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment

  @valid_reasons ~w[duplicate fraudulent customer_request dispute_retracted requested_by_merchant]
  # pending_approval → approved → requested → succeeded|failed
  # Direct path (no approval needed): requested → succeeded|failed
  @valid_states ~w[pending_approval approved requested succeeded failed rejected]

  schema "refunds" do
    field :public_id, :string
    field :amount, :integer
    field :currency, :string
    field :reason, :string
    field :state, :string, default: "requested"
    field :failure_reason, :string
    field :metadata, :map, default: %{}

    # Audit trail
    field :initiated_by, :string
    field :approved_by, :string
    field :approved_at, :utc_datetime_usec
    field :approval_reason, :string
    field :provider_ref, :string
    field :provider_response, :map
    field :state_transitions, {:array, :map}, default: []

    belongs_to :payment, Payment
    belongs_to :merchant, Merchant
    belongs_to :dispute, Dispute

    timestamps()
  end

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, [
      :payment_id,
      :merchant_id,
      :dispute_id,
      :amount,
      :currency,
      :reason,
      :metadata,
      :initiated_by,
      :state
    ])
    |> validate_required([:payment_id, :merchant_id, :amount, :currency, :reason])
    |> validate_inclusion(:reason, @valid_reasons)
    |> validate_inclusion(:state, @valid_states)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> put_public_id()
    |> put_initial_transition()
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:merchant_id)
    |> foreign_key_constraint(:dispute_id)
    |> unique_constraint(:public_id)
  end

  def approve_changeset(refund, approved_by, reason) do
    now = DateTime.utc_now(:microsecond)
    transition = transition_entry(refund.state, "approved", approved_by, reason)

    refund
    |> change(
      state: "approved",
      approved_by: approved_by,
      approved_at: now,
      approval_reason: reason
    )
    |> append_transition(transition)
    |> check_constraint(:approved_by,
      name: :sod_approver_differs_from_initiator,
      message: "approver cannot be the same as the initiator"
    )
  end

  def reject_changeset(refund, rejected_by, reason) do
    transition = transition_entry(refund.state, "rejected", rejected_by, reason)

    refund
    |> change(state: "rejected", failure_reason: reason)
    |> append_transition(transition)
  end

  def dispatch_changeset(refund) do
    transition = transition_entry(refund.state, "requested", "system", nil)

    refund
    |> change(state: "requested")
    |> append_transition(transition)
  end

  def settle_changeset(refund, provider_ref \\ nil, provider_response \\ nil) do
    transition = transition_entry(refund.state, "succeeded", "system", nil)
    attrs = %{state: "succeeded", state_transitions: refund.state_transitions ++ [transition]}
    attrs = if provider_ref, do: Map.put(attrs, :provider_ref, provider_ref), else: attrs

    attrs =
      if provider_response, do: Map.put(attrs, :provider_response, provider_response), else: attrs

    change(refund, attrs)
  end

  def fail_changeset(refund, reason) do
    transition = transition_entry(refund.state, "failed", "system", reason)

    refund
    |> change(
      state: "failed",
      failure_reason: reason,
      state_transitions: refund.state_transitions ++ [transition]
    )
  end

  def valid_states, do: @valid_states

  defp put_public_id(%{data: %{public_id: nil}} = changeset) do
    put_change(changeset, :public_id, "ref_" <> Uniq.UUID.uuid7())
  end

  defp put_public_id(changeset), do: changeset

  defp put_initial_transition(changeset) do
    state = get_field(changeset, :state) || "requested"
    by = get_field(changeset, :initiated_by) || "system"
    transition = transition_entry(nil, state, by, nil)
    put_change(changeset, :state_transitions, [transition])
  end

  defp append_transition(changeset, transition) do
    current = get_field(changeset, :state_transitions) || []
    put_change(changeset, :state_transitions, current ++ [transition])
  end

  defp transition_entry(from, to, by, reason) do
    entry = %{
      "from" => from,
      "to" => to,
      "at" => DateTime.utc_now(:microsecond) |> DateTime.to_iso8601(),
      "by" => by
    }

    if reason, do: Map.put(entry, "reason", reason), else: entry
  end
end
