defmodule YagyeCoreWeb.ApiSpecs.ComplianceSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse
  alias YagyeCoreWeb.Contracts.Compliance.{SubmitOnboardingRequest, SubmitBeneficialOwnerRequest, UploadKybDocumentRequest}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  defp merchant_id_param do
    %Parameter{
      name: :merchant_id,
      in: :path,
      description: "Merchant public ID",
      required: true,
      schema: %Schema{type: :string}
    }
  end

  def operation(:submit_onboarding) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Submit onboarding details",
      operationId: "ComplianceController.submit_onboarding",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      requestBody: %RequestBody{
        description: "Onboarding details",
        required: true,
        content: json(SubmitOnboardingRequest)
      },
      responses: %{
        200 => %Response{description: "Onboarding submitted; merchant returned with updated state"},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:add_beneficial_owner) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Add a beneficial owner",
      operationId: "ComplianceController.add_beneficial_owner",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      requestBody: %RequestBody{
        description: "Beneficial owner details",
        required: true,
        content: json(SubmitBeneficialOwnerRequest)
      },
      responses: %{
        201 => %Response{description: "Beneficial owner added"},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:upload_document) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Upload a KYB document",
      operationId: "ComplianceController.upload_document",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      requestBody: %RequestBody{
        description: "Document metadata",
        required: true,
        content: json(UploadKybDocumentRequest)
      },
      responses: %{
        201 => %Response{description: "Document record created"},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end
end
