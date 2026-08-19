defmodule YagyeCoreWeb.ApiSpecs.ApiKeySpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Schemas.ErrorResponse
  alias YagyeCoreWeb.Schemas.ApiKeys.{ApiKey, IssueApiKeyRequest}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["API Keys"],
      summary: "Issue an API key",
      description:
        "The full key value is returned **once only** in the `key` field. Store it immediately — it cannot be retrieved again.",
      operationId: "ApiKeyController.create",
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
        description: "Key attributes",
        required: true,
        content: json(IssueApiKeyRequest)
      },
      responses: %{
        201 => %Response{description: "API key issued", content: json(ApiKey)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:delete) do
    %Operation{
      tags: ["API Keys"],
      summary: "Revoke an API key",
      operationId: "ApiKeyController.delete",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :merchant_id,
          in: :path,
          description: "Merchant public ID",
          required: true,
          schema: %Schema{type: :string}
        },
        %Parameter{
          name: :id,
          in: :path,
          description: "API key public ID",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{description: "API key revoked", content: json(ApiKey)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end
end
