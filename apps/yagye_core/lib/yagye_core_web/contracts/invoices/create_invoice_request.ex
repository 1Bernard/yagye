defmodule YagyeCoreWeb.Contracts.Invoices.CreateInvoiceRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateInvoiceRequest",
    type: :object,
    properties: %{
      customer_reference: %Schema{
        type: :string,
        description: "Your own identifier for the customer (merchant_customer_ref)"
      },
      currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code",
        minLength: 3,
        maxLength: 3
      },
      number: %Schema{
        type: :string,
        description:
          "Merchant invoice number (must be unique per merchant). Gapless sequential numbers e.g. INV-00123 are a legal requirement in many jurisdictions."
      },
      issue_date: %Schema{
        type: :string,
        format: :date,
        description: "Date invoice is issued (YYYY-MM-DD)"
      },
      due_date: %Schema{
        type: :string,
        format: :date,
        description: "Date payment is due (YYYY-MM-DD)"
      },
      notes: %Schema{
        type: :string,
        description: "Free-text notes shown to the customer",
        nullable: true
      },
      terms: %Schema{
        type: :string,
        description: "Payment terms shown to the customer",
        nullable: true
      },
      line_items: %Schema{
        type: :array,
        minItems: 1,
        items: %Schema{
          type: :object,
          properties: %{
            description: %Schema{type: :string},
            quantity: %Schema{type: :number, minimum: 0, exclusiveMinimum: true},
            unit_amount: %Schema{
              type: :integer,
              description: "Unit price in minor units",
              minimum: 0
            },
            tax_rate_bps: %Schema{
              type: :integer,
              description: "Tax rate in basis points (e.g. 1500 = 15.00%)",
              minimum: 0
            }
          },
          required: [:description, :quantity, :unit_amount, :tax_rate_bps]
        }
      }
    },
    required: [:customer_reference, :currency, :number, :issue_date, :due_date, :line_items],
    example: %{
      "customer_reference" => "cust_abc123",
      "currency" => "GHS",
      "number" => "INV-00042",
      "issue_date" => "2026-08-30",
      "due_date" => "2026-09-30",
      "notes" => "Thank you for your business.",
      "line_items" => [
        %{
          "description" => "API Platform — August 2026",
          "quantity" => 1,
          "unit_amount" => 50_000,
          "tax_rate_bps" => 1500
        }
      ]
    }
  })
end
