defmodule YagyeCoreWeb.Contracts.Compliance.UploadKybDocumentRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UploadKybDocumentRequest",
    type: :object,
    required: [:kind, :checksum, :uploaded_by],
    properties: %{
      kind: %Schema{
        type: :string,
        enum: ["incorporation", "id", "proof_of_address", "bank_confirmation"],
        description: "Document type"
      },
      s3_key: %Schema{
        type: :string,
        description:
          "S3 object key — omit to have the platform generate a pending placeholder. Provide this only when you are uploading directly to S3 with your own presigned URL.",
        example: "kyb/mch_abc/incorporation/cert.pdf"
      },
      checksum: %Schema{
        type: :string,
        description: "SHA-256 checksum of the uploaded file (hex-encoded)",
        example: "a3f5e8..."
      },
      uploaded_by: %Schema{
        type: :string,
        description: "Identifier of the user or system that performed the upload",
        example: "user:usr_018e..."
      }
    },
    example: %{
      "kind" => "incorporation",
      "checksum" => "a3f5e8b2c1d4",
      "uploaded_by" => "user:usr_018e4a1b"
    }
  })
end
