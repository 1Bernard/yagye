defmodule YagyeCheckoutWeb.LinkController do
  use Phoenix.Controller, formats: [:html]

  alias YagyeCheckout.CoreClient

  # GET /:slug — creates a checkout session from the payment link slug and
  # redirects to the tokenized checkout URL so the session isn't reused on refresh.
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> html("""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Yagye Pay</title>
      <style>
        body { margin: 0; display: flex; align-items: center; justify-content: center;
               min-height: 100svh; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
               background: #f9fafb; color: #111827; }
        .card { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px;
                padding: 2.5rem 2rem; max-width: 380px; width: 100%; text-align: center;
                box-shadow: 0 1px 3px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.06); }
        .icon { width: 48px; height: 48px; background: #f3f4f6; border-radius: 50%;
                display: flex; align-items: center; justify-content: center; margin: 0 auto 1.25rem; }
        h1 { font-size: 1.125rem; font-weight: 700; margin: 0 0 .5rem; }
        p { font-size: .875rem; color: #6b7280; line-height: 1.6; margin: 0; }
        .brand { display: flex; align-items: center; justify-content: center; gap: .375rem;
                 font-size: .75rem; font-weight: 600; color: #3D47F5; margin-top: 2rem; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24"
            fill="none" stroke="#9ca3af" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>
            <line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
        </div>
        <h1>No payment link</h1>
        <p>This URL doesn't point to a payment link. Please use the full link you received from the merchant.</p>
        <div class="brand">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
            fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          </svg>
          Secured by Yagye
        </div>
      </div>
    </body>
    </html>
    """)
  end

  def redirect_to_session(conn, %{"slug" => slug}) do
    case CoreClient.create_session_from_link(slug) do
      {:ok, %{"token" => token}} ->
        redirect(conn, to: "/s/#{token}")

      {:error, %{"error" => error}} when error in ~w[link_not_found link_inactive link_expired] ->
        redirect(conn, to: "/s/__not_found__")

      {:error, body} when is_map(body) ->
        error = Map.get(body, "error", "unavailable")
        redirect(conn, to: "/s/__#{error}__")

      {:error, _} ->
        redirect(conn, to: "/s/__error__")
    end
  end
end
