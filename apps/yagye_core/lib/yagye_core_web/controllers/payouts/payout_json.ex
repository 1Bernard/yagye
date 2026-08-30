defmodule YagyeCoreWeb.Controllers.Payouts.PayoutJSON do
  @moduledoc false

  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}

  def list(%{data: payouts, has_more: has_more}) do
    %{object: "list", data: Enum.map(payouts, &data/1), has_more: has_more}
  end

  def data(%Payout{} = p) do
    %{
      id: p.public_id,
      object: "payout",
      mode: p.mode,
      amount: p.amount,
      currency: p.currency,
      destination_type: p.destination_type,
      state: p.state,
      provider_reference: p.provider_reference,
      scheduled_for: p.scheduled_for,
      submitted_at: p.submitted_at,
      completed_at: p.completed_at,
      failure_code: p.failure_code,
      inserted_at: p.inserted_at
    }
  end

  def destination_list(destinations) do
    %{object: "list", data: Enum.map(destinations, &destination_data/1)}
  end

  def destination_data(%PayoutDestination{} = d) do
    %{
      id: d.public_id,
      object: "payout_destination",
      mode: d.mode,
      kind: d.kind,
      currency: d.currency,
      account_name_verified: d.account_name_verified,
      verification_state: d.verification_state,
      is_default: d.is_default,
      active: d.active,
      inserted_at: d.inserted_at
    }
  end
end
