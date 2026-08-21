defmodule YagyeCoreWeb.Contracts.Disputes.Refund do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Refund",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Refund public ID (ref_…)"},
      object: %Schema{type: :string, enum: ["refund"]},
      payment_id: %Schema{type: :string, description: "Payment public ID"},
      dispute_id: %Schema{
        type: :string,
        nullable: true,
        description: "Dispute retracted by this refund, if any"
      },
      amount: %Schema{type: :integer, description: "Refunded amount in minor units"},
      currency: %Schema{type: :string},
      reason: %Schema{type: :string},
      state: %Schema{type: :string, enum: ["requested", "succeeded", "failed"]},
      failure_reason: %Schema{type: :string, nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  })
end
