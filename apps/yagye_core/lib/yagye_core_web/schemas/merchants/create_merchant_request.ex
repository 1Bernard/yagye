defmodule YagyeCoreWeb.Schemas.Merchants.CreateMerchantRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateMerchantRequest",
    type: :object,
    properties: %{
      legal_name: %Schema{type: :string, description: "Legal registered business name"},
      trading_name: %Schema{type: :string, description: "Trading or DBA name"},
      country: %Schema{type: :string, description: "ISO 3166-1 alpha-2 country code", minLength: 2, maxLength: 2},
      default_currency: %Schema{type: :string, description: "ISO 4217 currency code", minLength: 3, maxLength: 3},
      metadata: %Schema{type: :object, description: "Arbitrary key-value pairs"}
    },
    required: [:legal_name, :trading_name, :country, :default_currency],
    example: %{
      "legal_name" => "Acme Payments Ltd",
      "trading_name" => "Acme Pay",
      "country" => "GB",
      "default_currency" => "GBP"
    }
  })
end
