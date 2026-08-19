defmodule YagyeCoreWeb.Schemas.Compliance.SubmitBeneficialOwnerRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SubmitBeneficialOwnerRequest",
    type: :object,
    required: [:subject_ref, :role],
    properties: %{
      subject_ref: %Schema{
        type: :string,
        format: :uuid,
        description: "UUID reference to the PII vault entry holding this person's personal data"
      },
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
      "subject_ref" => "018e4a1b-b0d4-7000-b9c2-f9c8e8d2ae4a",
      "role" => "ubo",
      "ownership_bps" => 5000
    }
  })
end
