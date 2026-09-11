defmodule YagyeCoreWeb.Controllers.Internal.CheckoutController do
  use YagyeCoreWeb, :controller

  require Logger

  alias YagyeCore.Checkout.Schemas.CheckoutSession
  alias YagyeCore.CheckoutSessions
  alias YagyeCore.Payments

  # GET /internal/checkout/sessions/by-token?token=:raw_token
  def session_by_token(conn, %{"token" => token}) do
    case CheckoutSessions.get_session_by_token(token) do
      {:ok, session} ->
        checkout_layout = fetch_checkout_layout(session.payment_link_id)

        conn
        |> put_status(:ok)
        |> json(Map.put(render_session(session), :checkout_layout, checkout_layout))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def session_by_token(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "token param required"})
  end

  # POST /internal/checkout/sessions/from-link
  def create_from_link(conn, %{"slug" => slug}) do
    case CheckoutSessions.create_from_link(slug) do
      {:ok, {_session, url_token}} ->
        conn |> put_status(:ok) |> json(%{token: url_token})

      {:error, :link_inactive} ->
        conn |> put_status(:not_found) |> json(%{error: "link_inactive"})

      {:error, :link_expired} ->
        conn |> put_status(:not_found) |> json(%{error: "link_expired"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "link_not_found"})

      {:error, %Ecto.Changeset{} = cs} ->
        errors = Ecto.Changeset.traverse_errors(cs, &format_changeset_error/1)
        Logger.error("[checkout] session_creation_failed slug=#{slug} errors=#{inspect(errors)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "session_creation_failed", details: errors})

      {:error, reason} ->
        Logger.error("[checkout] session_creation_failed slug=#{slug} reason=#{inspect(reason)}")
        conn |> put_status(:unprocessable_entity) |> json(%{error: "session_creation_failed"})
    end
  end

  # POST /internal/checkout/sessions/:public_id/pay
  # Body: {method, msisdn, network}
  def pay(conn, %{"public_id" => public_id} = params) do
    with {:ok, session} <- CheckoutSessions.get_session_by_public_id(public_id),
         :ok <- validate_session_open(session),
         {:ok, {payment, _event}} <- create_payment(session, params),
         {:ok, _updated} <- CheckoutSessions.begin_processing(session, payment.id) do
      conn
      |> put_status(:ok)
      |> json(%{payment_public_id: payment.public_id, session_state: "processing"})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :session_not_open} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "session_not_open"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  # GET /internal/checkout/payments/:payment_public_id/state
  def payment_state(conn, %{"payment_public_id" => pub_id}) do
    case Payments.get_payment(pub_id) do
      {:ok, payment} ->
        conn |> put_status(:ok) |> json(%{state: payment.state, payment_public_id: pub_id})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # POST /internal/checkout/sessions/:public_id/complete
  # Body: {payment_public_id}
  def complete(conn, %{"public_id" => public_id, "payment_public_id" => payment_pub_id}) do
    with {:ok, session} <- CheckoutSessions.get_session_by_public_id(public_id),
         {:ok, payment} <- Payments.get_payment(payment_pub_id),
         {:ok, completed} <- CheckoutSessions.complete_session(session, payment.id) do
      conn
      |> put_status(:ok)
      |> json(%{
        session_state: completed.state,
        success_url: completed.success_url,
        cancel_url: completed.cancel_url
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp validate_session_open(%CheckoutSession{state: "open"}), do: :ok
  defp validate_session_open(_session), do: {:error, :session_not_open}

  defp create_payment(session, params) do
    attrs = %{
      method: params["method"] || "mobile_money",
      rail: "fiat_provider",
      amount: session.total_amount,
      currency: session.currency,
      merchant_reference: session.merchant_reference,
      description: session.description || "Checkout payment",
      metadata: %{
        "msisdn" => params["msisdn"],
        "network" => params["network"] || "MTN",
        "checkout_session_id" => session.public_id
      }
    }

    Payments.create_payment(session.merchant_id, attrs)
  end

  defp fetch_checkout_layout(nil), do: nil

  defp fetch_checkout_layout(payment_link_id) do
    alias YagyeCore.PaymentLinks.Schemas.PaymentLink
    alias YagyeCore.Repo

    case Repo.get(PaymentLink, payment_link_id) do
      nil -> nil
      link -> link.checkout_layout
    end
  end

  defp render_session(%CheckoutSession{} = s) do
    %{
      public_id: s.public_id,
      state: s.state,
      description: s.description,
      total_amount: s.total_amount,
      subtotal_amount: s.subtotal_amount || s.total_amount,
      tax_amount: s.tax_amount || 0,
      shipping_amount: s.shipping_amount || 0,
      discount_amount: s.discount_amount || 0,
      currency: s.currency,
      allowed_methods: s.allowed_methods,
      collect_email: s.collect_email,
      collect_phone: s.collect_phone,
      collect_name: s.collect_name,
      expires_at: s.expires_at,
      success_url: s.success_url,
      cancel_url: s.cancel_url,
      metadata: s.metadata,
      line_items:
        Enum.map(s.line_items || [], fn item ->
          %{
            id: item.id,
            position: item.position,
            kind: item.kind,
            description: item.description,
            quantity: item.quantity,
            unit_amount: item.unit_amount,
            total_amount: item.total_amount,
            image_url: item.image_url
          }
        end)
    }
  end

  defp format_changeset_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, val}, acc ->
      String.replace(acc, "%{#{key}}", to_string(val))
    end)
  end
end
