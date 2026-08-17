defmodule YagyeCoreWeb.Router do
  use YagyeCoreWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: YagyeCoreWeb.ApiSpec
  end

  # Full auth + idempotency pipeline for merchant-facing v1 endpoints.
  # Authorize is applied per-controller-action (different scopes per route).
  # CORS: add corsica here in P2 when browser-callable publishable-key routes exist.
  pipeline :v1 do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: YagyeCoreWeb.ApiSpec
    plug YagyeCoreWeb.Plugs.AuditLog
    plug YagyeCoreWeb.Plugs.RateLimit
    plug YagyeCoreWeb.Plugs.Authenticate
    plug YagyeCoreWeb.Plugs.VerifyMode
    plug YagyeCoreWeb.Plugs.Idempotency
  end

  alias YagyeCoreWeb.Controllers.ApiKeys.ApiKeyController
  alias YagyeCoreWeb.Controllers.Compliance.ComplianceController
  alias YagyeCoreWeb.Controllers.Merchants.MerchantController

  # Spec and interactive docs (unauthenticated)
  scope "/api" do
    pipe_through :api
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/" do
    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # v1 merchant-facing API
  scope "/v1" do
    pipe_through :v1

    resources "/merchants", MerchantController, only: [:create, :show] do
      post "/approve", MerchantController, :approve

      resources "/keys", ApiKeyController, only: [:create, :delete]

      post "/onboarding", ComplianceController, :submit_onboarding
      post "/beneficial-owners", ComplianceController, :add_beneficial_owner
      post "/documents", ComplianceController, :upload_document
    end
  end

  scope "/api", YagyeCoreWeb do
    pipe_through :api
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
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: YagyeCoreWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
