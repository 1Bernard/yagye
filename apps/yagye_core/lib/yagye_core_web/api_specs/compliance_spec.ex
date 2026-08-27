defmodule YagyeCoreWeb.ApiSpecs.ComplianceSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse

  alias YagyeCoreWeb.Contracts.Compliance.{
    SubmitBeneficialOwnerRequest,
    SubmitOnboardingRequest,
    UploadKybDocumentRequest
  }

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
        200 => %Response{
          description: "Onboarding submitted; merchant returned with updated state"
        },
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

  def operation(:list_beneficial_owners) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "List beneficial owners",
      operationId: "ComplianceController.list_beneficial_owners",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      responses: %{
        200 => %Response{description: "List of beneficial owners"},
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
        description:
          "Document metadata. Omit s3_key to receive a platform-generated placeholder; provide it only when uploading directly to S3.",
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

  def operation(:list_documents) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "List KYB documents",
      operationId: "ComplianceController.list_documents",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      responses: %{
        200 => %Response{description: "List of KYB documents"},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:screening_status) do
    %Operation{
      tags: ["Compliance / KYB"],
      summary: "Get AML screening status",
      operationId: "ComplianceController.screening_status",
      security: [%{"bearer_auth" => []}],
      parameters: [merchant_id_param()],
      responses: %{
        200 => %Response{description: "Screening subjects and open hits for this merchant"},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end
end
