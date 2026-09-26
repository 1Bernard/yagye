defmodule YagyeCoreWeb.Controllers.Payments.PaymentJSON do
  @moduledoc false

  alias YagyeCore.Payments.Schemas.{Payment, PaymentEvent}

  def data(%Payment{} = p) do
    net_amount = if p.fee_amount, do: p.amount - p.fee_amount, else: nil

    %{
      id: p.public_id,
      object: "payment",
      mode: p.mode,
      amount: p.amount,
      fee_amount: p.fee_amount,
      net_amount: net_amount,
      currency: p.currency,
      state: p.state,
      rail: p.rail,
      method: p.method,
      merchant_reference: p.merchant_reference,
      description: p.description,
      metadata: p.metadata,
      inserted_at: p.inserted_at
    }
  end

  def event_list(events) do
    %{object: "list", data: Enum.map(events, &event_data/1)}
  end

  defp event_data(%PaymentEvent{} = e) do
    %{
      object: "payment_event",
      version: e.version,
      event_type: e.event_type,
      from_state: e.from_state,
      to_state: e.to_state,
      actor: e.actor,
      correlation_id: e.correlation_id,
      occurred_at: e.occurred_at
    }
  end
end
