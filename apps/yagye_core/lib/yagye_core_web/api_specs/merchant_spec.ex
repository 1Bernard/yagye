defmodule YagyeCoreWeb.ApiSpecs.MerchantSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse
  alias YagyeCoreWeb.Contracts.Merchants.{CreateMerchantRequest, Merchant}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["Merchants"],
      summary: "Create a merchant",
      operationId: "MerchantController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Merchant attributes",
        required: true,
        content: json(CreateMerchantRequest)
      },
      responses: %{
        201 => %Response{description: "Merchant created", content: json(Merchant)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Merchants"],
      summary: "Retrieve a merchant",
      operationId: "MerchantController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{name: :id, in: :path, description: "Merchant public ID", required: true, schema: %Schema{type: :string}}
      ],
      responses: %{
        200 => %Response{description: "Merchant retrieved", content: json(Merchant)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:approve) do
    %Operation{
      tags: ["Merchants"],
      summary: "Approve a merchant",
      operationId: "MerchantController.approve",
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
      responses: %{
        200 => %Response{description: "Merchant approved", content: json(Merchant)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)},
        422 => %Response{description: "Invalid state transition", content: json(ErrorResponse)}
      }
    }
  end
end
