defmodule YagyeCoreWeb.Contracts.Disputes.CreateRefundRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateRefundRequest",
    type: :object,
    properties: %{
      amount: %Schema{
        type: :integer,
        description: "Refund amount in minor units. Must not exceed the original payment amount.",
        minimum: 1
      },
      reason: %Schema{
        type: :string,
        description: "Reason for the refund",
        enum: ["duplicate", "fraudulent", "customer_request"]
      },
      metadata: %Schema{type: :object, description: "Arbitrary key-value pairs"}
    },
    required: [:amount],
    example: %{
      "amount" => 10_000,
      "reason" => "customer_request"
    }
  })
end
