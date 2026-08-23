defmodule YagyeCoreWeb.ApiSpecs.SettlementSpec do
  @moduledoc false

  alias OpenApiSpex.{Operation, Parameter, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse

  defp json(schema), do: %{"application/json" => %OpenApiSpex.MediaType{schema: schema}}
  defp list_schema, do: %Schema{type: :object}
  defp object_schema, do: %Schema{type: :object}

  def operation(:index) do
    %Operation{
      tags: ["Settlements"],
      summary: "List settlements",
      operationId: "SettlementController.index",
      security: [%{"bearer_auth" => []}],
      responses: %{
        200 => %Response{description: "Settlement list", content: json(list_schema())}
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Settlements"],
      summary: "Retrieve a settlement",
      operationId: "SettlementController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Settlement", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:batch_index) do
    %Operation{
      tags: ["Settlements"],
      summary: "List settlement batches",
      operationId: "SettlementController.batch_index",
      security: [%{"bearer_auth" => []}],
      responses: %{
        200 => %Response{description: "Batch list", content: json(list_schema())}
      }
    }
  end

  def operation(:batch_show) do
    %Operation{
      tags: ["Settlements"],
      summary: "Retrieve a settlement batch",
      operationId: "SettlementController.batch_show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Settlement batch", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  defp id_param do
    %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
  end
end
