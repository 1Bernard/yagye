defmodule YagyeCoreWeb.Router do
  use YagyeCoreWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: YagyeCoreWeb.ApiSpec)
  end

  # Full auth + idempotency pipeline for merchant-facing v1 endpoints.
  # Authorize is applied per-controller-action (different scopes per route).
  # CORS: add corsica here in P2 when browser-callable publishable-key routes exist.
  pipeline :v1 do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: YagyeCoreWeb.ApiSpec)
    plug(YagyeCoreWeb.Plugs.AuditLog)
    plug(YagyeCoreWeb.Plugs.RateLimit)
    plug(YagyeCoreWeb.Plugs.Authenticate)
    plug(YagyeCoreWeb.Plugs.VerifyMode)
    plug(YagyeCoreWeb.Plugs.Idempotency)
  end

  alias YagyeCoreWeb.Controllers.ApiKeys.ApiKeyController
  alias YagyeCoreWeb.Controllers.CheckoutSessions.CheckoutSessionController
  alias YagyeCoreWeb.Controllers.Compliance.ComplianceController
  alias YagyeCoreWeb.Controllers.Customers.CustomerController
  alias YagyeCoreWeb.Controllers.Disputes.{DisputeController, RefundController}
  alias YagyeCoreWeb.Controllers.Internal.ApiKeysController, as: InternalApiKeysController
  alias YagyeCoreWeb.Controllers.Internal.ApplicationsController
  alias YagyeCoreWeb.Controllers.Internal.CheckoutController
  alias YagyeCoreWeb.Controllers.Internal.ComplianceController, as: InternalComplianceController
  alias YagyeCoreWeb.Controllers.Internal.MerchantsController, as: InternalMerchantsController

  alias YagyeCoreWeb.Controllers.Internal.ReconciliationController,
    as: InternalReconciliationController

  alias YagyeCoreWeb.Controllers.Internal.SettlementBatchApprovalsController
  alias YagyeCoreWeb.Controllers.Internal.SettlementControlsController

  alias YagyeCoreWeb.Controllers.Internal.PaymentLinksController,
    as: InternalPaymentLinksController

  alias YagyeCoreWeb.Controllers.Internal.InvoicesController, as: InternalInvoicesController
  alias YagyeCoreWeb.Controllers.Internal.InvoiceViewController

  alias YagyeCoreWeb.Controllers.Internal.CheckoutSessionsController,
    as: InternalCheckoutSessionsController

  alias YagyeCoreWeb.Controllers.Internal.CustomersController, as: InternalCustomersController

  alias YagyeCoreWeb.Controllers.Internal.DashboardController, as: InternalDashboardController
  alias YagyeCoreWeb.Controllers.Internal.PricingController, as: InternalPricingController

  alias YagyeCoreWeb.Controllers.Internal.SettlementBatchesController,
    as: InternalSettlementBatchesController

  alias YagyeCoreWeb.Controllers.Internal.KybController

  alias YagyeCoreWeb.Controllers.Fx.FxRateController
  alias YagyeCoreWeb.Controllers.Invoices.InvoiceController
  alias YagyeCoreWeb.Controllers.Merchants.MerchantController
  alias YagyeCoreWeb.Controllers.PaymentLinks.PaymentLinkController
  alias YagyeCoreWeb.Controllers.Payments.PaymentController
  alias YagyeCoreWeb.Controllers.Payouts.PayoutController
  alias YagyeCoreWeb.Controllers.Routing.RoutingConfigurationsController
  alias YagyeCoreWeb.Controllers.Routing.RoutingController
  alias YagyeCoreWeb.Controllers.Settlement.SettlementController

  alias YagyeCoreWeb.Controllers.Webhooks.{
    InternalWebhookEndpointsController,
    ProviderWebhookController,
    WebhookDeliveriesController,
    WebhookEndpointsController
  }

  # Internal service-to-service pipeline — portal → core ops actions.
  # Authenticated by X-Service-Token shared secret (see AuthenticateInternal plug).
  # Never exposed to merchants or the public internet (firewall rule in production).
  pipeline :internal do
    plug(:accepts, ["json"])
    plug(YagyeCoreWeb.Plugs.AuthenticateInternal)
  end

  # Provider-to-core inbound webhooks (no merchant auth, HMAC-verified in controller)
  pipeline :provider_webhooks do
    plug(:accepts, ["json"])
  end

  scope "/" do
    get("/health", YagyeCoreWeb.HealthController, :check)
  end

  scope "/provider-webhooks" do
    pipe_through(:provider_webhooks)
    # Native rail + simulator: platform-level credential, HMAC-SHA256
    post("/:provider_code", ProviderWebhookController, :receive)
    # External PSPs (Model B): merchant-scoped credential, PSP-specific signature
    post("/:provider_code/merchant/:merchant_id", ProviderWebhookController, :receive_external)
  end

  # Spec and interactive docs (unauthenticated)
  scope "/api" do
    pipe_through(:api)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  scope "/" do
    get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")
  end

  # Internal ops endpoints — portal → core (KYB disposition, etc.)
  scope "/internal" do
    pipe_through(:internal)

    post("/applications/:application_id/approve", ApplicationsController, :approve)
    post("/applications/:application_id/reject", ApplicationsController, :reject)

    # Internal key provisioning — portal uses service token, not merchant API key
    post("/merchants/:code/keys", InternalApiKeysController, :create)

    # P13 — Routing rules management (Yagye ops + enterprise merchants at P16)
    get("/routing-rules", RoutingController, :index)
    post("/routing-rules", RoutingController, :create)
    get("/routing-rules/:id", RoutingController, :show)
    post("/routing-rules/:id/deactivate", RoutingController, :deactivate)

    # P13 — Routing configurations (graph-based editor)
    get("/routing-configurations", RoutingConfigurationsController, :index)
    post("/routing-configurations", RoutingConfigurationsController, :create)
    get("/routing-configurations/:id", RoutingConfigurationsController, :show)
    patch("/routing-configurations/:id", RoutingConfigurationsController, :update)
    post("/routing-configurations/:id/publish", RoutingConfigurationsController, :publish)

    # P16 — Hosted checkout (called by yagye_checkout service)
    post("/checkout/sessions/from-link", CheckoutController, :create_from_link)
    get("/checkout/sessions/by-token", CheckoutController, :session_by_token)
    post("/checkout/sessions/:public_id/pay", CheckoutController, :pay)
    get("/checkout/payments/:payment_public_id/state", CheckoutController, :payment_state)

    post(
      "/checkout/payments/:payment_public_id/simulate_transfer",
      CheckoutController,
      :simulate_transfer
    )

    post("/checkout/sessions/:public_id/complete", CheckoutController, :complete)

    # Compliance — portal ops view (read and write via service token)
    get(
      "/merchants/:merchant_id/beneficial-owners",
      InternalComplianceController,
      :list_beneficial_owners
    )

    post(
      "/merchants/:merchant_id/beneficial-owners",
      InternalComplianceController,
      :add_beneficial_owner
    )

    get("/merchants/:merchant_id/documents", InternalComplianceController, :list_documents)

    get(
      "/merchants/:merchant_id/screening-status",
      InternalComplianceController,
      :screening_status
    )

    # KYB merchant self-service (portal → core, called on merchant's behalf)
    get("/merchants/:merchant_code/kyb-status", KybController, :show_kyb_status)
    patch("/merchants/:merchant_code/kyb-profile", KybController, :update_kyb_profile)
    put("/merchants/:merchant_code/contacts", KybController, :upsert_contact)
    put("/merchants/:merchant_code/addresses/:address_type", KybController, :upsert_address)
    post("/merchants/:merchant_code/documents", KybController, :upload_document)
    post("/merchants/:merchant_code/service-agreements", KybController, :accept_agreement)

    # Ops-initiated full KYB approval (enforces 25% UBO screening threshold)
    post("/merchants/:merchant_code/kyb-approve", InternalMerchantsController, :kyb_approve)

    # Reconciliation — ops view of breaks per merchant and cross-merchant
    get(
      "/merchants/:merchant_id/reconciliation-breaks",
      InternalReconciliationController,
      :list_breaks
    )

    get("/reconciliation-breaks/:id", InternalReconciliationController, :get_break)

    post(
      "/reconciliation-breaks/:id/propose-adjustment",
      InternalReconciliationController,
      :propose_adjustment
    )

    get("/reconciliation-breaks", InternalReconciliationController, :list_all_breaks)

    # Settlement controls + dispatch approvals (portal → core)
    get("/merchants/:merchant_id/settlement-controls", SettlementControlsController, :show)
    put("/merchants/:merchant_id/settlement-controls", SettlementControlsController, :upsert)

    # Dashboard KPIs (portal ops view + merchant settlement summary)
    get("/dashboard/ops", InternalDashboardController, :ops_summary)

    get(
      "/merchants/:merchant_code/dashboard/settlement",
      InternalDashboardController,
      :merchant_settlement
    )

    post(
      "/settlement-batches/:batch_id/approve-dispatch",
      SettlementBatchApprovalsController,
      :approve
    )

    post(
      "/settlement-batches/:batch_id/reject-dispatch",
      SettlementBatchApprovalsController,
      :reject
    )

    # P16 — Payment links management (called by portal)
    get("/payment-links", InternalPaymentLinksController, :index)
    post("/payment-links", InternalPaymentLinksController, :create)
    get("/payment-links/:public_id", InternalPaymentLinksController, :show)
    post("/payment-links/:public_id/deactivate", InternalPaymentLinksController, :deactivate)

    patch(
      "/payment-links/:public_id/checkout-layout",
      InternalPaymentLinksController,
      :update_checkout_layout
    )

    # P13 — Invoices (portal read/write via service token)
    get("/merchants/:merchant_code/invoices", InternalInvoicesController, :index)
    post("/invoices", InternalInvoicesController, :create)
    get("/invoices/:id", InternalInvoicesController, :show)
    get("/invoices/:public_id/view", InvoiceViewController, :show)
    patch("/invoices/:id", InternalInvoicesController, :update)
    post("/invoices/:id/issue", InternalInvoicesController, :issue)
    post("/invoices/:id/void", InternalInvoicesController, :void)

    # P16 — Checkout Sessions (portal read-only via service token)
    get("/merchants/:merchant_code/checkout-sessions", InternalCheckoutSessionsController, :index)
    get("/checkout-sessions/:id", InternalCheckoutSessionsController, :show)

    # P11 — Customers (portal read-only via service token)
    get("/merchants/:merchant_code/customers", InternalCustomersController, :index)
    get("/customers/:id", InternalCustomersController, :show)

    # P9 — Settlement Batches (portal read-only via service token)
    get(
      "/merchants/:merchant_code/settlement-batches",
      InternalSettlementBatchesController,
      :index
    )

    get("/settlement-batches-info/:id", InternalSettlementBatchesController, :show)

    # Pricing — merchant rate card and fee invoices
    get("/merchants/:merchant_code/pricing-plan", InternalPricingController, :show_plan)
    get("/merchants/:merchant_code/fee-invoices", InternalPricingController, :list_fee_invoices)

    # FX rates — no merchant context needed, read-only reference data
    get("/fx-rates", YagyeCoreWeb.Controllers.Fx.FxRateController, :index)

    # P15 — Webhook endpoints (portal → core via service token)
    post(
      "/merchants/:merchant_code/webhook-endpoints",
      InternalWebhookEndpointsController,
      :create
    )

    patch(
      "/merchants/:merchant_code/webhook-endpoints/:endpoint_id",
      InternalWebhookEndpointsController,
      :update
    )

    delete(
      "/merchants/:merchant_code/webhook-endpoints/:endpoint_id",
      InternalWebhookEndpointsController,
      :delete
    )

    post(
      "/merchants/:merchant_code/webhook-endpoints/:endpoint_id/test",
      InternalWebhookEndpointsController,
      :test
    )

    post("/webhook-deliveries/retry", InternalWebhookEndpointsController, :retry_delivery)
  end

  # v1 merchant-facing API
  scope "/v1" do
    pipe_through(:v1)

    resources "/payments", PaymentController, only: [:create, :show], param: "id" do
      get("/events", PaymentController, :events)
      post("/disputes", DisputeController, :create)
      post("/refunds", RefundController, :create)
    end

    get("/disputes/:id", DisputeController, :show)
    get("/refunds/:id", RefundController, :show)

    resources "/merchants", MerchantController, only: [:create, :show] do
      post("/approve", MerchantController, :approve)

      resources("/keys", ApiKeyController, only: [:create, :delete])

      post("/onboarding", ComplianceController, :submit_onboarding)
      post("/beneficial-owners", ComplianceController, :add_beneficial_owner)
      get("/beneficial-owners", ComplianceController, :list_beneficial_owners)
      put("/beneficial-owners/:id", ComplianceController, :update_beneficial_owner)
      delete("/beneficial-owners/:id", ComplianceController, :delete_beneficial_owner)
      post("/documents", ComplianceController, :upload_document)
      get("/documents", ComplianceController, :list_documents)
      get("/screening-status", ComplianceController, :screening_status)
    end

    # P11 — Customers & Account Verifications
    get("/customers", CustomerController, :index)
    get("/customers/:id", CustomerController, :show)
    get("/account-verifications", CustomerController, :verifications_index)
    get("/account-verifications/:id", CustomerController, :verifications_show)

    # P9 — Settlement Batches
    get("/settlement-batches", SettlementController, :batch_index)
    get("/settlement-batches/:id", SettlementController, :batch_show)

    # P12 — Settlements & Payouts
    get("/settlements", SettlementController, :index)
    get("/settlements/:id", SettlementController, :show)

    post("/payout-destinations", PayoutController, :create_destination)
    get("/payout-destinations", PayoutController, :destinations_index)
    get("/payout-destinations/:id", PayoutController, :destinations_show)

    post("/payouts", PayoutController, :create)
    get("/payouts", PayoutController, :index)
    get("/payouts/:id", PayoutController, :show)

    # P15 — Outbound webhook endpoints (merchant self-service via their API key)
    post("/webhook-endpoints", WebhookEndpointsController, :create)
    patch("/webhook-endpoints/:endpoint_id", WebhookEndpointsController, :update)
    delete("/webhook-endpoints/:endpoint_id", WebhookEndpointsController, :delete)
    post("/webhook-endpoints/:endpoint_id/test", WebhookEndpointsController, :test)
    post("/webhook-deliveries/retry", WebhookDeliveriesController, :retry)

    # P13 — Invoices
    resources "/invoices", InvoiceController, only: [:create, :index, :show], param: "id" do
      post("/issue", InvoiceController, :issue)
      post("/void", InvoiceController, :void)
    end

    # P16 — Payment Links
    resources "/payment-links", PaymentLinkController,
      only: [:create, :index, :show],
      param: "id" do
      post("/deactivate", PaymentLinkController, :deactivate)
    end

    # P16 — Checkout Sessions (server-side create / read / expire)
    resources "/checkout-sessions", CheckoutSessionController,
      only: [:create, :index, :show],
      param: "id" do
      post("/expire", CheckoutSessionController, :expire)
    end

    # FX rates — current non-expired rates for display currency conversion
    get("/fx-rates", FxRateController, :index)
  end

  scope "/api", YagyeCoreWeb do
    pipe_through(:api)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:yagye_core, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: YagyeCoreWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
