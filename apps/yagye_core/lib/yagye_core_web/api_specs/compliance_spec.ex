defmodule YagyeCoreWeb.ApiSpecs.ComplianceSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Schemas.ErrorResponse

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}
  defp object_schema, do: %Schema{type: :object}

  def operation(:submit_onboarding) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Submit onboarding details",
      operationId: "ComplianceController.submit_onboarding",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :merchant_id,
          in: :path,
          description: "Merchant public ID",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      requestBody: %RequestBody{
        description: "Onboarding details",
        required: true,
        content: json(object_schema())
      },
      responses: %{
        200 => %Response{description: "Merchant with updated onboarding state", content: json(object_schema())},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:add_beneficial_owner) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Add a beneficial owner",
      operationId: "ComplianceController.add_beneficial_owner",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :merchant_id,
          in: :path,
          description: "Merchant public ID",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      requestBody: %RequestBody{
        description: "Beneficial owner details",
        required: true,
        content: json(object_schema())
      },
      responses: %{
        201 => %Response{description: "Beneficial owner added", content: json(object_schema())},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:upload_document) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Upload a KYB document",
      operationId: "ComplianceController.upload_document",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :merchant_id,
          in: :path,
          description: "Merchant public ID",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      requestBody: %RequestBody{
        description: "Document metadata",
        required: true,
        content: json(object_schema())
      },
      responses: %{
        201 => %Response{description: "Document uploaded", content: json(object_schema())},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end
end
