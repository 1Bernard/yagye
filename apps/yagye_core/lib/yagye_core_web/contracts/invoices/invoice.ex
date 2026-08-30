defmodule YagyeCoreWeb.Contracts.Invoices.Invoice do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Invoice",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Invoice public ID (inv_...)"},
      object: %Schema{type: :string, enum: ["invoice"]},
      mode: %Schema{type: :string, enum: ["simulation", "sandbox", "live"]},
      number: %Schema{type: :string, description: "Merchant-facing invoice number"},
      state: %Schema{
        type: :string,
        enum: ["draft", "open", "partially_paid", "paid", "void", "uncollectible", "overdue"]
      },
      currency: %Schema{type: :string},
      subtotal_amount: %Schema{
        type: :integer,
        description: "Sum of line items before tax/discount"
      },
      tax_amount: %Schema{type: :integer},
      discount_amount: %Schema{type: :integer},
      total_amount: %Schema{type: :integer},
      amount_paid: %Schema{type: :integer},
      amount_due: %Schema{type: :integer},
      issue_date: %Schema{type: :string, format: :date},
      due_date: %Schema{type: :string, format: :date},
      notes: %Schema{type: :string, nullable: true},
      terms: %Schema{type: :string, nullable: true},
      sent_at: %Schema{type: :string, format: :"date-time", nullable: true},
      paid_at: %Schema{type: :string, format: :"date-time", nullable: true},
      voided_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    example: %{
      "id" => "inv_01JXYZ",
      "object" => "invoice",
      "mode" => "simulation",
      "number" => "INV-00042",
      "state" => "draft",
      "currency" => "GHS",
      "subtotal_amount" => 50_000,
      "tax_amount" => 7_500,
      "discount_amount" => 0,
      "total_amount" => 57_500,
      "amount_paid" => 0,
      "amount_due" => 57_500,
      "issue_date" => "2026-08-30",
      "due_date" => "2026-09-30",
      "notes" => nil,
      "terms" => nil,
      "sent_at" => nil,
      "paid_at" => nil,
      "voided_at" => nil,
      "inserted_at" => "2026-08-30T06:00:00Z"
    }
  })
end
