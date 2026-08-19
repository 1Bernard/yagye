defmodule YagyeCoreWeb.Controllers.Payments.PaymentJSON do
  @moduledoc false

  alias YagyeCore.Payments.Schemas.Payment

  def data(%Payment{} = p) do
    %{
      id: p.public_id,
      object: "payment",
      mode: p.mode,
      amount: p.amount,
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
end
