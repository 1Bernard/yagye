defmodule YagyeCheckoutWeb.Router do
  use Phoenix.Router, helpers: false

  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YagyeCheckoutWeb.Layouts, :checkout}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline' cdn.jsdelivr.net; " <>
          "style-src 'self' 'unsafe-inline' fonts.googleapis.com; " <>
          "font-src fonts.gstatic.com; " <>
          "img-src 'self' data:; " <>
          "connect-src 'self' ws: wss:;"
    }
  end

  scope "/s" do
    pipe_through :browser
    live "/:token", YagyeCheckoutWeb.Live.CheckoutLive, :index
  end

  scope "/" do
    pipe_through :browser
    get "/health", YagyeCheckoutWeb.HealthController, :check
    get "/favicon.ico", YagyeCheckoutWeb.LinkController, :not_found
    get "/", YagyeCheckoutWeb.LinkController, :not_found
    get "/:slug", YagyeCheckoutWeb.LinkController, :redirect_to_session
  end
end
