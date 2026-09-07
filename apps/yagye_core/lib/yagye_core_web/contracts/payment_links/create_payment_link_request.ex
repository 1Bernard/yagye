defmodule YagyeCoreWeb.Contracts.PaymentLinks.CreatePaymentLinkRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreatePaymentLinkRequest",
    type: :object,
    properties: %{
      kind: %Schema{
        type: :string,
        enum: ["fixed_amount", "customer_specified", "invoice"],
        description:
          "fixed_amount: fixed price; customer_specified: buyer enters amount; invoice: attached to an invoice"
      },
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code",
        minLength: 3,
        maxLength: 3
      },
      amount: %Schema{
        type: :integer,
        description:
          "Amount in minor units (pesewas). Required for fixed_amount, must be omitted for customer_specified.",
        minimum: 1,
        nullable: true
      },
      description: %Schema{
        type: :string,
        description: "What is being sold or collected"
      },
      image_url: %Schema{
        type: :string,
        description: "Product or brand image shown on the checkout page",
        nullable: true
      },
      allowed_methods: %Schema{
        type: :array,
        items: %Schema{
          type: :string,
          enum: ["mobile_money", "card", "bank_transfer"]
        },
        description: "Payment methods to offer. Defaults to all active methods for the merchant."
      },
      collect_email: %Schema{type: :boolean, description: "Show email field on checkout"},
      collect_phone: %Schema{type: :boolean, description: "Show phone field on checkout"},
      collect_name: %Schema{type: :boolean, description: "Show full-name field on checkout"},
      reusable: %Schema{
        type: :boolean,
        description: "Whether the link can be paid multiple times. Default true."
      },
      max_uses: %Schema{
        type: :integer,
        description: "Maximum number of successful payments (nil = unlimited)",
        minimum: 1,
        nullable: true
      },
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "UTC timestamp after which the link becomes inactive",
        nullable: true
      },
      url_slug: %Schema{
        type: :string,
        description: "Custom URL slug (auto-generated if omitted)",
        nullable: true
      },
      metadata: %Schema{
        type: :object,
        description: "Arbitrary key-value pairs attached to the link",
        nullable: true
      }
    },
    required: [:kind, :currency, :description],
    example: %{
      "kind" => "fixed_amount",
      "currency" => "GHS",
      "amount" => 5000,
      "description" => "Premium plan — September 2026",
      "collect_email" => true,
      "collect_name" => true,
      "reusable" => true
    }
  })
end
