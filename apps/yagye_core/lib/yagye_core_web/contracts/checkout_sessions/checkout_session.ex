defmodule YagyeCoreWeb.Contracts.CheckoutSessions.CheckoutSession do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CheckoutSession",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Public ID (cks_...)"},
      object: %Schema{type: :string, enum: ["checkout_session"]},
      mode: %Schema{type: :string, enum: ["simulation", "sandbox", "live"]},
      checkout_url: %Schema{type: :string, description: "Full URL to redirect the customer to"},
      state: %Schema{
        type: :string,
        enum: ["open", "processing", "completed", "cancelled", "expired"]
      },
      currency: %Schema{type: :string},
      subtotal_amount: %Schema{type: :integer},
      tax_amount: %Schema{type: :integer},
      shipping_amount: %Schema{type: :integer},
      discount_amount: %Schema{type: :integer},
      total_amount: %Schema{type: :integer},
      description: %Schema{type: :string, nullable: true},
      merchant_reference: %Schema{type: :string},
      collect_email: %Schema{type: :boolean},
      collect_phone: %Schema{type: :boolean},
      collect_name: %Schema{type: :boolean},
      allowed_methods: %Schema{type: :array, items: %Schema{type: :string}},
      payment_link_id: %Schema{type: :string, nullable: true},
      payment_id: %Schema{type: :string, nullable: true},
      success_url: %Schema{type: :string, nullable: true},
      cancel_url: %Schema{type: :string, nullable: true},
      metadata: %Schema{type: :object, nullable: true},
      expires_at: %Schema{type: :string, format: :"date-time"},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      line_items: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            position: %Schema{type: :integer},
            kind: %Schema{type: :string},
            description: %Schema{type: :string},
            quantity: %Schema{type: :integer},
            unit_amount: %Schema{type: :integer},
            total_amount: %Schema{type: :integer},
            image_url: %Schema{type: :string, nullable: true}
          }
        }
      },
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  })
end
