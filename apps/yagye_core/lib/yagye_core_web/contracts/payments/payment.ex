defmodule YagyeCoreWeb.Contracts.Payments.Payment do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Payment",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Payment public ID (pay_...)"},
      object: %Schema{type: :string, enum: ["payment"]},
      mode: %Schema{type: :string, enum: ["simulation", "live"]},
      amount: %Schema{type: :integer, description: "Amount in minor units"},
      currency: %Schema{type: :string, description: "ISO 4217 currency code"},
      state: %Schema{
        type: :string,
        enum: ["created", "processing", "requires_action", "authorised",
               "succeeded", "failed", "cancelled", "indeterminate"]
      },
      rail: %Schema{type: :string, enum: ["fiat_provider", "internal"]},
      method: %Schema{type: :string, nullable: true},
      merchant_reference: %Schema{type: :string, nullable: true},
      description: %Schema{type: :string, nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    example: %{
      "id" => "pay_01JXYZ",
      "object" => "payment",
      "mode" => "simulation",
      "amount" => 10000,
      "currency" => "GHS",
      "state" => "created",
      "rail" => "fiat_provider",
      "method" => "mobile_money",
      "merchant_reference" => "order_abc123",
      "description" => "Payment for order #abc123",
      "metadata" => %{},
      "inserted_at" => "2026-08-19T12:00:00Z"
    }
  })
end
