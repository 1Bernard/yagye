defmodule Simulator.Web.Router do
  use Phoenix.Router, helpers: false

  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug Simulator.Web.Plugs.AuthenticateAccount
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Simulator.Web.Layouts, :admin}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:; font-src 'self';"
    }
  end

  # ── Provider API (authenticated with x-api-key) ───────────────────────────────

  scope "/", Simulator.Web.Controllers do
    pipe_through :api

    post "/charges", ChargeController, :create
    get "/charges/:ref", ChargeController, :show

    post "/charges/:ref/refunds", RefundController, :create
    get "/refunds/:ref", RefundController, :show

    post "/name-enquiry", NameEnquiryController, :create
  end

  # ── OpenAPI spec (unauthenticated — it's a dev tool) ─────────────────────────

  scope "/api" do
    pipe_through [:browser]

    get "/openapi", OpenApiSpex.Plug.RenderSpec, spec: Simulator.Web.ApiSpec
    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # ── LiveView admin (unauthenticated — dev tool, add auth before staging) ─────

  scope "/admin", Simulator.Web do
    pipe_through :browser

    live "/scenarios", Live.ScenarioLive, :index
  end
end
