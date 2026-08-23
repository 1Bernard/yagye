defmodule YagyeCoreWeb.ApiSpecs.CustomerSpec do
  @moduledoc false

  alias OpenApiSpex.{Operation, Parameter, Response, Schema}
  alias YagyeCoreWeb.Contracts.ErrorResponse

  defp json(schema), do: %{"application/json" => %OpenApiSpex.MediaType{schema: schema}}
  defp list_schema, do: %Schema{type: :object}
  defp object_schema, do: %Schema{type: :object}

  def operation(:index) do
    %Operation{
      tags: ["Customers"],
      summary: "List customers",
      operationId: "CustomerController.index",
      security: [%{"bearer_auth" => []}],
      responses: %{200 => %Response{description: "Customer list", content: json(list_schema())}}
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Customers"],
      summary: "Retrieve a customer",
      operationId: "CustomerController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Customer", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:verifications_index) do
    %Operation{
      tags: ["Customers"],
      summary: "List account verifications",
      operationId: "CustomerController.verifications_index",
      security: [%{"bearer_auth" => []}],
      responses: %{
        200 => %Response{description: "Verification list", content: json(list_schema())}
      }
    }
  end

  def operation(:verifications_show) do
    %Operation{
      tags: ["Customers"],
      summary: "Retrieve an account verification",
      operationId: "CustomerController.verifications_show",
      security: [%{"bearer_auth" => []}],
      parameters: [id_param()],
      responses: %{
        200 => %Response{description: "Account verification", content: json(object_schema())},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  defp id_param do
    %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
  end
end
