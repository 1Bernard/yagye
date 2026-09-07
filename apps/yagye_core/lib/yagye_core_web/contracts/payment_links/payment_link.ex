defmodule YagyeCoreWeb.Contracts.PaymentLinks.PaymentLink do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentLink",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Public ID (plk_...)"},
      object: %Schema{type: :string, enum: ["payment_link"]},
      mode: %Schema{type: :string, enum: ["simulation", "sandbox", "live"]},
      url_slug: %Schema{type: :string},
      checkout_url: %Schema{type: :string, description: "Full URL customers use to pay"},
      kind: %Schema{type: :string, enum: ["fixed_amount", "customer_specified", "invoice"]},
      amount: %Schema{type: :integer, nullable: true},
      currency: %Schema{type: :string},
      description: %Schema{type: :string},
      image_url: %Schema{type: :string, nullable: true},
      allowed_methods: %Schema{type: :array, items: %Schema{type: :string}},
      collect_email: %Schema{type: :boolean},
      collect_phone: %Schema{type: :boolean},
      collect_name: %Schema{type: :boolean},
      reusable: %Schema{type: :boolean},
      max_uses: %Schema{type: :integer, nullable: true},
      use_count: %Schema{type: :integer},
      active: %Schema{type: :boolean},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  })
end
