defmodule YagyeCoreWeb.Contracts.Disputes.CreateDisputeRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateDisputeRequest",
    type: :object,
    properties: %{
      network: %Schema{
        type: :string,
        description: "Network or scheme that raised the dispute",
        enum: ["MTN", "TELECEL", "AIRTELTIGO", "VISA", "MASTERCARD", "GH_INTERBANK"]
      },
      reason: %Schema{
        type: :string,
        description: "Dispute reason code",
        enum: [
          "duplicate",
          "fraud",
          "credit_not_processed",
          "product_not_received",
          "subscription_cancelled"
        ]
      },
      amount: %Schema{
        type: :integer,
        description: "Disputed amount in minor units. Defaults to full payment amount.",
        minimum: 1
      },
      metadata: %Schema{type: :object, description: "Arbitrary key-value pairs"}
    },
    required: [:network, :reason],
    example: %{
      "network" => "MTN",
      "reason" => "fraud",
      "amount" => 10_000
    }
  })
end
