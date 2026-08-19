defmodule YagyeCoreWeb.Contracts.ApiKeys.IssueApiKeyRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "IssueApiKeyRequest",
    type: :object,
    properties: %{
      kind: %Schema{type: :string, enum: ["publishable", "secret"]},
      mode: %Schema{type: :string, enum: ["simulation", "sandbox", "live"]},
      scopes: %Schema{type: :array, items: %Schema{type: :string}, example: ["merchants:read"]},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:kind, :mode, :scopes],
    example: %{
      "kind" => "secret",
      "mode" => "simulation",
      "scopes" => ["merchants:read", "merchants:write", "api_keys:write"]
    }
  })
end
