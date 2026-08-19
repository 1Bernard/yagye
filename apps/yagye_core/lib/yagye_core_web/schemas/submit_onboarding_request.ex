defmodule YagyeCoreWeb.Schemas.SubmitOnboardingRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SubmitOnboardingRequest",
    type: :object,
    required: [:business_type],
    properties: %{
      business_type: %Schema{
        type: :string,
        description: "Type of business (e.g. retail, ecommerce, saas)",
        example: "ecommerce"
      },
      website_url: %Schema{
        type: :string,
        description: "Primary website URL",
        example: "https://acmepay.com"
      },
      expected_monthly_volume_minor: %Schema{
        type: :integer,
        description: "Expected monthly processing volume in minor currency units",
        example: 5_000_000
      },
      expected_monthly_volume_currency: %Schema{
        type: :string,
        description: "ISO 4217 currency code for the expected monthly volume",
        minLength: 3,
        maxLength: 3,
        example: "GBP"
      }
    },
    example: %{
      "business_type" => "ecommerce",
      "website_url" => "https://acmepay.com",
      "expected_monthly_volume_minor" => 5_000_000,
      "expected_monthly_volume_currency" => "GBP"
    }
  })
end
