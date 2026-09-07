defmodule YagyeCoreWeb.Contracts.CheckoutSessions.CreateCheckoutSessionRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateCheckoutSessionRequest",
    type: :object,
    properties: %{
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code",
        minLength: 3,
        maxLength: 3
      },
      subtotal_amount: %Schema{
        type: :integer,
        description: "Subtotal in minor units (e.g. pesewas)",
        minimum: 0
      },
      tax_amount: %Schema{type: :integer, minimum: 0, nullable: true},
      shipping_amount: %Schema{type: :integer, minimum: 0, nullable: true},
      discount_amount: %Schema{type: :integer, minimum: 0, nullable: true},
      total_amount: %Schema{
        type: :integer,
        description: "Must equal subtotal + tax + shipping - discount",
        minimum: 1
      },
      description: %Schema{type: :string, description: "Shown on the checkout page"},
      merchant_reference: %Schema{
        type: :string,
        description: "Your own order or reference ID",
        nullable: true
      },
      success_url: %Schema{
        type: :string,
        description: "Redirect URL after successful payment"
      },
      cancel_url: %Schema{
        type: :string,
        description: "Redirect URL if the customer cancels"
      },
      allowed_methods: %Schema{
        type: :array,
        items: %Schema{type: :string, enum: ["mobile_money", "card", "bank_transfer"]},
        nullable: true
      },
      collect_email: %Schema{type: :boolean, nullable: true},
      collect_phone: %Schema{type: :boolean, nullable: true},
      collect_name: %Schema{type: :boolean, nullable: true},
      mode: %Schema{
        type: :string,
        enum: ["simulation", "sandbox", "live"],
        description: "Defaults to the merchant's current active mode",
        nullable: true
      },
      line_items: %Schema{
        type: :array,
        nullable: true,
        items: %Schema{
          type: :object,
          properties: %{
            kind: %Schema{type: :string, enum: ["item", "shipping", "tax", "discount"]},
            description: %Schema{type: :string},
            quantity: %Schema{type: :integer, minimum: 1},
            unit_amount: %Schema{
              type: :integer,
              description: "Negative for discount items"
            },
            total_amount: %Schema{type: :integer},
            image_url: %Schema{type: :string, nullable: true}
          },
          required: [:kind, :description, :quantity, :unit_amount, :total_amount]
        }
      },
      metadata: %Schema{type: :object, nullable: true}
    },
    required: [:currency, :subtotal_amount, :total_amount, :success_url, :cancel_url],
    example: %{
      "currency" => "GHS",
      "subtotal_amount" => 5000,
      "tax_amount" => 750,
      "shipping_amount" => 0,
      "discount_amount" => 0,
      "total_amount" => 5750,
      "description" => "Order #00123",
      "success_url" => "https://example.com/order/success",
      "cancel_url" => "https://example.com/order/cancel",
      "line_items" => [
        %{
          "kind" => "item",
          "description" => "Premium plan",
          "quantity" => 1,
          "unit_amount" => 5000,
          "total_amount" => 5000
        }
      ]
    }
  })
end
