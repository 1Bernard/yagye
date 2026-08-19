defmodule YagyeCoreWeb.Contracts.ApiKeys.ApiKey do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ApiKey",
    description: "An API key — the secret field is present only on creation and never again",
    type: :object,
    properties: %{
      id: %Schema{type: :string, example: "key_019526ab3e7f7b4fa19b8be26eac7d14"},
      object: %Schema{type: :string, enum: ["api_key"]},
      kind: %Schema{type: :string, enum: ["publishable", "secret"]},
      mode: %Schema{type: :string, enum: ["simulation", "sandbox", "live"]},
      key_prefix: %Schema{type: :string, description: "First 24 chars — safe to log and display", example: "4eC39HqLyjWDarjtT7zdgkd1"},
      key: %Schema{type: :string, description: "Full key — returned ONCE on creation only, never stored", example: "4eC39HqLyjWDarjtT7zdgkd1Axcj3a4eC39HqLyjWD"},
      scopes: %Schema{type: :array, items: %Schema{type: :string}, example: ["merchants:read", "api_keys:write"]},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      revoked_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :object, :kind, :mode, :key_prefix, :scopes]
  })
end
