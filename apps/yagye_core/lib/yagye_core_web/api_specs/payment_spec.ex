defmodule YagyeCoreWeb.ApiSpecs.PaymentSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, RequestBody, Response}
  alias YagyeCoreWeb.Contracts.ErrorResponse
  alias YagyeCoreWeb.Contracts.Payments.{CreatePaymentRequest, Payment}

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["Payments"],
      summary: "Create a payment",
      operationId: "PaymentController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Payment attributes",
        required: true,
        content: json(CreatePaymentRequest)
      },
      responses: %{
        201 => %Response{description: "Payment created", content: json(Payment)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)},
        404 => %Response{description: "Merchant not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Payments"],
      summary: "Retrieve a payment",
      operationId: "PaymentController.show",
      security: [%{"bearer_auth" => []}],
      responses: %{
        200 => %Response{description: "Payment retrieved", content: json(Payment)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end
end
