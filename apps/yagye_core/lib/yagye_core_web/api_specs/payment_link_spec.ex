defmodule YagyeCoreWeb.ApiSpecs.PaymentLinkSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse
  alias YagyeCoreWeb.Contracts.PaymentLinks.{CreatePaymentLinkRequest, PaymentLink}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["Payment Links"],
      summary: "Create a payment link",
      operationId: "PaymentLinkController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Payment link configuration",
        required: true,
        content: json(CreatePaymentLinkRequest)
      },
      responses: %{
        201 => %Response{description: "Payment link created", content: json(PaymentLink)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:index) do
    %Operation{
      tags: ["Payment Links"],
      summary: "List payment links",
      operationId: "PaymentLinkController.index",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :active,
          in: :query,
          description: "Filter by active state",
          schema: %Schema{type: :boolean}
        },
        %Parameter{
          name: :limit,
          in: :query,
          description: "Maximum results (default 50, max 100)",
          schema: %Schema{type: :integer, minimum: 1, maximum: 100}
        },
        %Parameter{
          name: :starting_after,
          in: :query,
          description: "Cursor: return links after this public_id",
          schema: %Schema{type: :string}
        },
        %Parameter{
          name: :ending_before,
          in: :query,
          description: "Cursor: return links before this public_id",
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{
          description: "List of payment links",
          content:
            json(%Schema{
              type: :object,
              properties: %{
                object: %Schema{type: :string, enum: ["list"]},
                data: %Schema{type: :array, items: PaymentLink},
                has_more: %Schema{type: :boolean}
              }
            })
        }
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Payment Links"],
      summary: "Retrieve a payment link",
      operationId: "PaymentLinkController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          description: "Payment link public ID (plk_...)",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{description: "Payment link retrieved", content: json(PaymentLink)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:deactivate) do
    %Operation{
      tags: ["Payment Links"],
      summary: "Deactivate a payment link",
      description:
        "Sets the link to inactive. Invoice-backed links cannot be deactivated — void the invoice instead.",
      operationId: "PaymentLinkController.deactivate",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{description: "Payment link deactivated", content: json(PaymentLink)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)},
        422 => %Response{description: "Cannot deactivate", content: json(ErrorResponse)}
      }
    }
  end
end
