defmodule YagyeCoreWeb.Schemas.Merchant do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Merchant",
    description: "A merchant account",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Public merchant ID", example: "mch_019526ab3e7f7b4fa19b8be26eac7d14"},
      object: %Schema{type: :string, enum: ["merchant"]},
      legal_name: %Schema{type: :string, example: "Acme Payments Ltd"},
      trading_name: %Schema{type: :string, example: "Acme Pay"},
      country: %Schema{type: :string, description: "ISO 3166-1 alpha-2", minLength: 2, maxLength: 2, example: "GB"},
      default_currency: %Schema{type: :string, description: "ISO 4217", minLength: 3, maxLength: 3, example: "GBP"},
      status: %Schema{type: :string, enum: ["registered", "approved", "suspended", "closed"]},
      onboarding_state: %Schema{type: :string, enum: ["registered", "submitted", "under_review", "approved", "rejected"]},
      activity_state: %Schema{type: :string, enum: ["active", "dormant", "suspended"]},
      api_version: %Schema{type: :string, example: "2026-01-01"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :object, :legal_name, :trading_name, :country, :default_currency, :status],
    example: %{
      "id" => "mch_019526ab3e7f7b4fa19b8be26eac7d14",
      "object" => "merchant",
      "legal_name" => "Acme Payments Ltd",
      "trading_name" => "Acme Pay",
      "country" => "GB",
      "default_currency" => "GBP",
      "status" => "registered",
      "onboarding_state" => "registered",
      "activity_state" => "active",
      "api_version" => "2026-01-01",
      "inserted_at" => "2026-08-17T10:00:00.000000Z"
    }
  })
end
