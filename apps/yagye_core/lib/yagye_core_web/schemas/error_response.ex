defmodule YagyeCoreWeb.Schemas.ErrorResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    description: "Standard error envelope — matches Stripe/OpenAI error shape",
    type: :object,
    properties: %{
      error: %Schema{
        type: :object,
        properties: %{
          type: %Schema{type: :string, example: "invalid_request_error"},
          code: %Schema{type: :string, example: "validation_failed"},
          message: %Schema{type: :string, example: "Country must be a 2-letter ISO code"},
          param: %Schema{type: :string, description: "Field that caused the error", example: "country"},
          details: %Schema{type: :object, description: "Field-level validation errors"}
        },
        required: [:type, :code, :message]
      }
    },
    required: [:error],
    example: %{
      "error" => %{
        "type" => "invalid_request_error",
        "code" => "validation_failed",
        "message" => "Country must be a 2-letter ISO code",
        "param" => "country"
      }
    }
  })
end
