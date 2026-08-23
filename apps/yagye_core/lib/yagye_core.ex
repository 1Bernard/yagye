defmodule YagyeCore do
  use Boundary,
    exports: [
      Merchants,
      Merchants.Schemas.Merchant,
      Merchants.Schemas.ApiKey,
      Compliance,
      Compliance.Schemas.BeneficialOwner,
      Compliance.Schemas.KybDocument,
      Disputes,
      Disputes.Schemas.Dispute,
      Disputes.Schemas.Refund,
      Idempotency,
      Shared.ApiRequest,
      Shared.RateLimiter,
      Shared.Schema,
      Payments,
      Payments.ProviderAdapter,
      Payments.Schemas.Payment,
      Payments.Schemas.PaymentAttempt,
      Payments.Schemas.PaymentEvent,
      Providers,
      Providers.Schemas.Provider,
      Providers.Schemas.ProviderCredential,
      Providers.Schemas.MerchantProviderConnection,
      Shared.Vault,
      Ledger,
      Ledger.Schemas.Account,
      Ledger.Schemas.Entry,
      Ledger.Schemas.Posting,
      Ledger.Schemas.Balance,
      Settlement,
      Settlement.Schemas.SettlementBatch,
      Webhooks,
      Webhooks.Schemas.WebhookEvent,
      Repo
    ]

  @moduledoc """
  YagyeCore keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
end
