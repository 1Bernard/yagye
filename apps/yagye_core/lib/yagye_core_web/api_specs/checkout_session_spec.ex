defmodule YagyeCoreWeb.ApiSpecs.CheckoutSessionSpec do
  @moduledoc false

  alias OpenApiSpex.{MediaType, Operation, Parameter, RequestBody, Response, Schema}
  alias YagyeCoreWeb.Contracts.CheckoutSessions.{CheckoutSession, CreateCheckoutSessionRequest}
  alias YagyeCoreWeb.Contracts.ErrorResponse

  defp json(schema), do: %{"application/json" => %MediaType{schema: schema}}

  def operation(:create) do
    %Operation{
      tags: ["Checkout Sessions"],
      summary: "Create a checkout session",
      description:
        "Creates a hosted checkout session. Redirect your customer to the returned `checkout_url`.",
      operationId: "CheckoutSessionController.create",
      security: [%{"bearer_auth" => []}],
      requestBody: %RequestBody{
        description: "Session configuration",
        required: true,
        content: json(CreateCheckoutSessionRequest)
      },
      responses: %{
        201 => %Response{description: "Session created", content: json(CheckoutSession)},
        422 => %Response{description: "Validation error", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:show) do
    %Operation{
      tags: ["Checkout Sessions"],
      summary: "Retrieve a checkout session",
      operationId: "CheckoutSessionController.show",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          description: "Checkout session public ID (cks_...)",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{description: "Session retrieved", content: json(CheckoutSession)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)}
      }
    }
  end

  def operation(:index) do
    %Operation{
      tags: ["Checkout Sessions"],
      summary: "List checkout sessions",
      operationId: "CheckoutSessionController.index",
      security: [%{"bearer_auth" => []}],
      parameters: [
        %Parameter{
          name: :state,
          in: :query,
          description: "Filter by session state",
          schema: %Schema{
            type: :string,
            enum: ["open", "processing", "completed", "cancelled", "expired"]
          }
        },
        %Parameter{
          name: :payment_link_id,
          in: :query,
          description: "Filter by payment link public ID",
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => %Response{
          description: "List of sessions",
          content:
            json(%Schema{
              type: :object,
              properties: %{
                object: %Schema{type: :string, enum: ["list"]},
                data: %Schema{type: :array, items: CheckoutSession}
              }
            })
        }
      }
    }
  end

  def operation(:expire) do
    %Operation{
      tags: ["Checkout Sessions"],
      summary: "Expire a session",
      description: "Manually expires an open or processing session.",
      operationId: "CheckoutSessionController.expire",
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
        200 => %Response{description: "Session expired", content: json(CheckoutSession)},
        404 => %Response{description: "Not found", content: json(ErrorResponse)},
        422 => %Response{description: "Cannot expire", content: json(ErrorResponse)}
      }
    }
  end
end
