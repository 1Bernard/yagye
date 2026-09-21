defmodule YagyeCoreWeb.Contracts.Compliance.UpdateBeneficialOwnerRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UpdateBeneficialOwnerRequest",
    type: :object,
    properties: %{
      role: %Schema{
        type: :string,
        enum: ["director", "ubo", "both"],
        description: "Role of this person in the business"
      },
      ownership_bps: %Schema{
        type: :integer,
        description: "Ownership percentage in basis points (0–10000, where 10000 = 100%)",
        minimum: 0,
        maximum: 10_000,
        example: 5000
      }
    },
    example: %{
      "role" => "both",
      "ownership_bps" => 3000
    }
  })
end
