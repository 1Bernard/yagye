defmodule YagyeCore do
  use Boundary,
    exports: [
      Merchants,
      Merchants.Schemas.Merchant,
      Merchants.Schemas.ApiKey,
      Compliance,
      Compliance.Schemas.BeneficialOwner,
      Compliance.Schemas.KybDocument,
      Idempotency,
      Shared.ApiRequest,
      Shared.RateLimiter,
      Shared.Schema,
      Payments,
      Payments.Schemas.Payment,
      Payments.Schemas.PaymentEvent
    ]

  @moduledoc """
  YagyeCore keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
end
