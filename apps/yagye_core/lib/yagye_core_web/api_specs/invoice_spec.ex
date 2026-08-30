defmodule YagyeCoreWeb.ApiSpecs.InvoiceSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse
  alias YagyeCoreWeb.Contracts.Invoices.{CreateInvoiceRequest, Invoice}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["Invoices"],
      summary: "Create an invoice",
      operationId: "InvoiceController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Invoice attributes and line items",
        required: true,
        content: json(CreateInvoiceRequest)
      },
      responses: %{
        201 => %Response{description: "Invoice created", content: json(Invoice)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)},
        404 => %Response{description: "Customer not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:index) do
    %Operation{
      tags: ["Invoices"],
      summary: "List invoices",
      operationId: "InvoiceController.index",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :state,
          in: :query,
          description: "Filter by invoice state",
          schema: %Schema{
            type: :string,
            enum: ["draft", "open", "partially_paid", "paid", "void", "uncollectible", "overdue"]
          }
        },
        %Parameter{
          name: :limit,
          in: :query,
          description: "Maximum number of results (default 50, max 100)",
          schema: %Schema{type: :integer, minimum: 1, maximum: 100}
        },
        %Parameter{
          name: :offset,
          in: :query,
          description: "Pagination offset",
          schema: %Schema{type: :integer, minimum: 0}
        }
      ],
      responses: %{
        200 => %Response{
          description: "List of invoices",
          content:
            json(%Schema{
              type: :object,
              properties: %{
                object: %Schema{type: :string, enum: ["list"]},
                data: %Schema{type: :array, items: Invoice}
              }
            })
        }
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Invoices"],
      summary: "Retrieve an invoice",
      operationId: "InvoiceController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          description: "Invoice public ID (inv_...)",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{description: "Invoice retrieved", content: json(Invoice)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:issue) do
    %Operation{
      tags: ["Invoices"],
      summary: "Issue a draft invoice",
      description: "Transitions the invoice from draft → open and makes it payable.",
      operationId: "InvoiceController.issue",
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
        200 => %Response{description: "Invoice issued", content: json(Invoice)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)},
        422 => %Response{description: "Invalid state transition", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:void) do
    %Operation{
      tags: ["Invoices"],
      summary: "Void an invoice",
      description:
        "Marks the invoice void. Voided invoices are preserved in full — they are never deleted.",
      operationId: "InvoiceController.void",
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
        200 => %Response{description: "Invoice voided", content: json(Invoice)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)},
        422 => %Response{description: "Invalid state transition", content: json(ErrorResponse)}
      }
    }
  end
end
