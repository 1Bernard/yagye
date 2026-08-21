defmodule YagyeCoreWeb.ApiSpecs.DisputeSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}

  alias YagyeCoreWeb.Contracts.Disputes.{
    CreateDisputeRequest,
    CreateRefundRequest,
    Dispute,
    Refund
  }

  alias YagyeCoreWeb.Contracts.ErrorResponse

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  defp payment_id_param do
    %Parameter{
      name: :payment_id,
      in: :path,
      description: "Payment public ID",
      required: true,
      schema: %Schema{type: :string}
    }
  end

  defp id_param(description) do
    %Parameter{
      name: :id,
      in: :path,
      description: description,
      required: true,
      schema: %Schema{type: :string}
    }
  end

  def operation(:create_dispute) do
    %Operation{
      tags: ["Disputes"],
      summary: "Inject a dispute for a payment",
      description:
        "Simulates a dispute raised by the network or card scheme. Use in simulation mode to test your dispute handling flows.",
      operationId: "DisputeController.create",
      security: [%{"bearer_auth" => []}],
      parameters: [payment_id_param()],
      requestBody: %RequestBody{
        description: "Dispute attributes",
        required: true,
        content: json(CreateDisputeRequest)
      },
      responses: %{
        201 => %Response{description: "Dispute created", content: json(Dispute)},
        404 => %Response{description: "Payment not found", content: json(ErrorResponse)},
        422 => %Response{
          description: "Payment not in a disputable state",
          content: json(ErrorResponse)
        }
      }
    }
  end

  def operation(:show_dispute) do
    %Operation{
      tags: ["Disputes"],
      summary: "Retrieve a dispute",
      operationId: "DisputeController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param("Dispute public ID")],
      responses: %{
        200 => %Response{description: "Dispute retrieved", content: json(Dispute)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:create_refund) do
    %Operation{
      tags: ["Refunds"],
      summary: "Issue a refund for a payment",
      description:
        "Creates a refund. If the payment has an open dispute, it is automatically retracted.",
      operationId: "RefundController.create",
      security: [%{"bearer_auth" => []}],
      parameters: [payment_id_param()],
      requestBody: %RequestBody{
        description: "Refund attributes",
        required: true,
        content: json(CreateRefundRequest)
      },
      responses: %{
        201 => %Response{description: "Refund created", content: json(Refund)},
        404 => %Response{description: "Payment not found", content: json(ErrorResponse)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:show_refund) do
    %Operation{
      tags: ["Refunds"],
      summary: "Retrieve a refund",
      operationId: "RefundController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param("Refund public ID")],
      responses: %{
        200 => %Response{description: "Refund retrieved", content: json(Refund)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end
end
