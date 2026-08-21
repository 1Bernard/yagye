defmodule YagyeCoreWeb.Contracts.Disputes.Dispute do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Dispute",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Dispute public ID (dsp_…)"},
      object: %Schema{type: :string, enum: ["dispute"]},
      payment_id: %Schema{type: :string, description: "Payment public ID"},
      network: %Schema{type: :string},
      reason: %Schema{type: :string},
      amount: %Schema{type: :integer},
      currency: %Schema{type: :string},
      stage: %Schema{
        type: :string,
        enum: ["opened", "evidence_required", "under_review", "resolved"]
      },
      outcome: %Schema{
        type: :string,
        nullable: true,
        enum: ["won", "lost", "retracted"]
      },
      evidence_due_at: %Schema{type: :string, format: :"date-time", nullable: true},
      resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  })
end
