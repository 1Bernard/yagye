defmodule YagyeCoreWeb.ApiSpecs.PayoutSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}
  defp list_schema, do: %Schema{type: :object}
  defp object_schema, do: %Schema{type: :object}

  def operation(:create) do
    %Operation{
      tags: ["Payouts"],
      summary: "Create a payout",
      operationId: "PayoutController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Payout attributes",
        required: true,
        content: json(%Schema{type: :object})
      },
      responses: %{
        201 => %Response{description: "Payout created", content: json(object_schema())},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:index) do
    %Operation{
      tags: ["Payouts"],
      summary: "List payouts",
      operationId: "PayoutController.index",
      security: [%{"bearer_auth" => []}],
      responses: %{200 => %Response{description: "Payout list", content: json(list_schema())}}
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Payouts"],
      summary: "Retrieve a payout",
      operationId: "PayoutController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Payout", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:create_destination) do
    %Operation{
      tags: ["Payouts"],
      summary: "Create a payout destination",
      operationId: "PayoutController.create_destination",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Destination attributes",
        required: true,
        content: json(%Schema{type: :object})
      },
      responses: %{
        201 => %Response{description: "Destination created", content: json(object_schema())},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:destinations_index) do
    %Operation{
      tags: ["Payouts"],
      summary: "List payout destinations",
      operationId: "PayoutController.destinations_index",
      security: [%{"bearer_auth" => []}],
      responses: %{
        200 => %Response{description: "Destination list", content: json(list_schema())}
      }
    }
  end

  def operation(:destinations_show) do
    %Operation{
      tags: ["Payouts"],
      summary: "Retrieve a payout destination",
      operationId: "PayoutController.destinations_show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Payout destination", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  defp id_param do
    %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
  end
end
