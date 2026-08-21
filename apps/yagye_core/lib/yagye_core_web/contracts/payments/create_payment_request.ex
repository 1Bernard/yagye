defmodule YagyeCoreWeb.Contracts.Payments.CreatePaymentRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreatePaymentRequest",
    type: :object,
    properties: %{
      amount: %Schema{
        type: :integer,
        description: "Amount in minor units (e.g. pesewas)",
        minimum: 1
      },
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code",
        minLength: 3,
        maxLength: 3
      },
      rail: %Schema{
        type: :string,
        description: "Payment rail",
        enum: ["fiat_provider", "internal"]
      },
      method: %Schema{type: :string, description: "Payment method (e.g. card, mobile_money)"},
      merchant_reference: %Schema{
        type: :string,
        description: "Merchant-supplied idempotency reference"
      },
      description: %Schema{type: :string, description: "Human-readable description"},
      metadata: %Schema{type: :object, description: "Arbitrary key-value pairs"}
    },
    required: [:amount, :currency, :rail],
    example: %{
      "amount" => 10_000,
      "currency" => "GHS",
      "rail" => "fiat_provider",
      "method" => "mobile_money",
      "merchant_reference" => "order_abc123",
      "description" => "Payment for order #abc123",
      "metadata" => %{"order_type" => "subscription", "customer_tier" => "gold"}
    }
  })
end
